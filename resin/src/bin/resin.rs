use byteorder::{ReadBytesExt, WriteBytesExt, NetworkEndian};
use resin::error::InternalError;
use serde::{Deserialize, Serialize};
use std::io::{self, Cursor, Read, Write};
use std::thread;
use std::process::{ChildStdin, Command, Stdio};
use std::sync::mpsc::{channel, Sender, Receiver};

/// StreamTy represents which standard file-descriptor a data packet
/// was read from. This is necessary to multiplex multiple descriptors
/// onto the single stream available for sending data back to the Erlang VM.
#[derive(Copy, Clone, Debug, Deserialize, Serialize)]
pub enum StreamTy {
	Stdout,
	Stderr,
}

/// PacketTy represents the valid list of data which is expected to be
/// exchanged over the Erlang VM port. This data will be CBOR encoded
/// on the wire.
#[derive(Debug, Deserialize, Serialize)]
pub enum PacketTy {
	/// Sent by a `shellac` client to request that the daemon starts
	/// the named executable. If this daemon is already running an
	/// executable: this command will be ignored and an error code
	/// will be returned to the client.
	StartProcess { exec: String, args: Vec<String> },

	/// Sent by a `shellac` client to request that the daemon stops
	/// the child process immediately.
	KillProcess,

	/// Data to be sent to a `shellac` client representing data
	/// received from the child's output descriptor(s).
	DataOut { ty: StreamTy, buf: Vec<u8> },


	/// Data received from a `shellac` client representing data
	/// which needs to be sent to the child program on its standard
	/// input descriptor.
	DataIn { buf: Vec<u8> },

	/// Indicates to a `shellac` client that the daemon will exit
	/// because the child has hung-up & returned an exit status.
	///
	/// NOTE: an exit status is not available on all platforms in
	/// all instances of abnormal termination. The `shellac` client
	/// must be able to handle the absence of an exit code.
	ExitStatus { code: Option<i32> },

	/// The daemon has encountered a non-fatal error.
	ErrorReport { msg: String },
}


#[derive(Debug)]
enum ServerState {
	NotStarted,
	Started,
}

#[derive(Debug)]
struct ResinServer {
	state: ServerState,
	child_stdin: Option<ChildStdin>,
	exit_tx: Option<Sender<()>>,
	exit_rx: Option<Receiver<()>>,
}

impl ResinServer {

	pub fn new() -> Self {
		let (exit_tx, exit_rx) = channel();

		ResinServer {
			state: ServerState::NotStarted,
			child_stdin: None,
			exit_tx: Some(exit_tx),
			exit_rx: Some(exit_rx),
		}
	}

	fn dispatch_packet(&mut self, packet: PacketTy) -> Result<(), InternalError> {
		match self.state {
			ServerState::NotStarted => self.dispatch_not_running(packet)?,
			ServerState::Started => self.dispatch_running(packet)?,
		}

		Ok(())
	}


	fn dispatch_not_running(&mut self, packet: PacketTy) -> Result<(), InternalError> {
		match packet {
			PacketTy::StartProcess { exec, args } => {
				// set up command per specs from client
				let mut child = Command::new(exec);
				for arg in args { child.arg(arg); }

				// setup input / output for use w/ daemon
				let mut child = child.stdin(Stdio::piped())
					.stdout(Stdio::piped())
					.stderr(Stdio::piped())
					.spawn()?;



				// pull out i/o for splitting into threads
				self.child_stdin = child.stdin.take();


				let stdout = child.stdout.take()
					.expect("stdout handle not opened?");

				let stderr = child.stderr.take()
					.expect("stderr handle not opened?");

				// set up message passing for threads
				let (outbox_tx, outbox_rx) = channel();

				let stdout_tx = outbox_tx.clone();
				let stderr_tx = outbox_tx.clone();
				let status_tx = outbox_tx.clone();


				// start i/o worker threads
				let _stdout_thread = thread::spawn(move || {
					handle_output(StreamTy::Stdout, stdout, stdout_tx)
				});

				let _stderr_thread = thread::spawn(move || {
					handle_output(StreamTy::Stderr, stderr, stderr_tx)
				});

				let exit_rx = self.exit_rx.take().unwrap();
				let _status_thread: thread::JoinHandle<Result<(), InternalError>> = thread::spawn(move || {
					loop {
						match exit_rx.try_recv() {
							Ok(_)  => child.kill()?,
							Err(_) => {},
						};

						match child.try_wait() {
							Ok(Some(status_code)) => {
								status_tx.send(PacketTy::ExitStatus { code: status_code.code() });
								std::process::exit(0);
							},

							Ok(None) | Err(_) => {},
						}

						// TODO: how long to wait here?
						// TODO: don't use sleep_ms
						std::thread::sleep_ms(100);
					}
				});


				let _outgoing_thread: thread::JoinHandle<Result<(), InternalError>> = thread::spawn(move || {
					let mut erlang_port = io::stdout();

					loop {
						match outbox_rx.recv() {
							Ok(packet) => {
								let buf = serde_cbor::to_vec(&packet)?;
								erlang_port.write_u16::<NetworkEndian>(buf.len() as u16)?;
								erlang_port.write(&buf)?;
								erlang_port.flush()?;
							},

							Err(_msg) => break, 
						}
					}

					Ok(())
				});

				// transition to running state
				self.state = ServerState::Started;

				Ok(())
			},

			msg => panic!("illegal packet {:?} for state {:?}", msg, self.state),
		}
	}

	fn dispatch_running(&mut self, packet: PacketTy) -> Result<(), InternalError> {
		match packet {
			PacketTy::DataIn { mut buf } => {
				if let Some(ref mut fd) = self.child_stdin {
					let mut cursor = Cursor::new(&mut buf);
					io::copy(&mut cursor, fd)?;
				}

				Ok(())
			},

			PacketTy::KillProcess => {
				if let Some(tx) = &self.exit_tx { tx.send(()); }
				Ok(())
			},

			msg => panic!("illegal packet {:?} for state {:?}", msg, self.state),
		}
	}



	fn dispatch_error(&mut self, error: InternalError) -> Result<(), InternalError> {
		let packet = PacketTy::ErrorReport {
			msg: format!("resin daemon error: {}", error)
		};

		let buf = serde_cbor::to_vec(&packet)?;
		
		let mut erlang_port = io::stdout();
		erlang_port.write_u16::<NetworkEndian>(buf.len() as u16)?;
		erlang_port.write(&buf)?;
		erlang_port.flush()?;

		Ok(())
	}
}


/// Takes a list of *one or more* wire-format packets and transforms them into
/// a higher-level application packet. It is assumed that all packets, except the
/// final packet, have their continuation bit set; furthermore each packet in the
/// list should be of the same type.
///
/// Mixing data from multiple packets will result in a failure during decoding.
///
fn decode_packets(packets: Vec<Vec<u8>>) -> Result<PacketTy, InternalError> {
	let complete_buf = packets
		.iter()
		.flat_map(|packet| { &packet[1..] })
		.map(|byte| *byte)
		.collect::<Vec<_>>();

	let decoded_packet = serde_cbor::from_reader(&complete_buf[..])?;

	Ok(decoded_packet)
}

/// This loop takes a stream and type descriptor, it reads data from the
/// stream into a fixed-length buffer and transforms it into application
/// packets which are sent to the outgoing packet queue.
///
/// This function blocks until reading from `stream` returns either `Ok(0)` 
/// or Err(...) as a result.
///
fn handle_output<R: Read>(stream_ty: StreamTy, mut stream: R, outbox: Sender<PacketTy>) -> Result<(), InternalError> {
	'stdout: loop {
		let mut buf = [0u8; 1024];
		let len = stream.read(&mut buf)?;
		if len == 0 { break 'stdout }

		let packet = PacketTy::DataOut { 
			ty: stream_ty,
			buf: buf[0..len].to_vec() 
		};

		// TODO: log failure 
		if let Err(_msg) = outbox.send(packet) { break 'stdout }
	}

	Ok(())
}


fn main() -> Result<(), InternalError> {
	let mut stdin = io::stdin();
	let mut packet_chain = vec![];
	let mut server = ResinServer::new();

	let exit_tx = server.exit_tx
		.clone()
		.take()
		.expect("could not acquire exit channel");

	'header: loop {
		// read packet size (first u16 on wire)
		let mut len_buf = [0u8; 2];
		let size = stdin.read(&mut len_buf)?;

		// TODO: well this is awkward, did they hang up?
		if size == 0 { break 'header }

		// assert we actually read a u16, then process `len` bytes
		assert_eq!(len_buf.len(), size);
		let packet_len = (&len_buf[..]).read_u16::<NetworkEndian>()?;
		let mut packet = vec![0u8; packet_len as usize];
		stdin.read_exact(&mut packet)?;

		// read packet flags, continue reading packets if necessary
		let is_finished = (packet[0] & 0x80) == 0;
		packet_chain.push(packet);
		if !is_finished { continue 'header; }

		// TODO: actually swap buffers here, instead of creating a new one?
		// swap buffers and decode packet
		let last_packet_group = std::mem::replace(&mut packet_chain, vec![]);
		let dispatch_result = match decode_packets(last_packet_group) {
			Ok(decoded_packet) => server.dispatch_packet(decoded_packet),
			Err(err) => server.dispatch_error(err),
		};

		if let Err(err) = dispatch_result {
			server
				.dispatch_error(err)
				.expect("error dispatching error; terminating on account of double fault.");
		}
	}

	// stdin hungup, let's leave ...
	exit_tx.send(());
	thread::sleep_ms(1000);
	Ok(())
}
