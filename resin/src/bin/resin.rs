use byteorder::{ReadBytesExt, WriteBytesExt, NetworkEndian};
use resin::error::InternalError;
use serde::{Deserialize, Serialize};
use std::io::{self, Read, Write};
use std::thread;
use std::process::{Command, Stdio};
use std::sync::mpsc::{channel, Sender, Receiver};


#[derive(Copy, Clone, Debug, Deserialize, Serialize)]
pub enum StreamTy {
	Stdout,
	Stderr,
}


#[derive(Debug, Deserialize, Serialize)]
pub enum PacketTy {
	/// Sent by a `shellac` client to request that the daemon starts
	/// the named executable. If this daemon is already running an
	/// executable: this command will be ignored and an error code
	/// will be returned to the client.
	StartProcess { exec: String, args: Vec<String> },

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
}

fn decode_packets(packets: Vec<Vec<u8>>) -> Result<PacketTy, InternalError> {
	let complete_buf = packets
		.iter()
		.flat_map(|packet| { &packet[1..] })
		.map(|byte| *byte)
		.collect::<Vec<_>>();

	let decoded_packet = serde_cbor::from_reader(&complete_buf[..])?;

	Ok(decoded_packet)
}

fn dispatch_packet(packet: PacketTy) -> Result<(), InternalError> {
	// echo length to client
	//stdout.write_u16::<NetworkEndian>(2)?;
	//stdout.write_u16::<NetworkEndian>(packet_len)?;
	//stdout.flush()?;
	
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


			let mut erlang_port = io::stdout();

			let mut stdin = child.stdin.take()
				.expect ("stdin handle not opened?");

			let mut stdout = child.stdout.take()
				.expect("stdout handle not opened?");

			let mut stderr = child.stderr.take()
				.expect("stderr handle not opened?");

			let (outbox_tx, outbox_rx) = channel();

			let stdout_tx = outbox_tx.clone();
			let stderr_tx = outbox_tx.clone();
			let status_tx = outbox_tx.clone();

			let stdout_thread = thread::spawn(move || {
				handle_output(StreamTy::Stdout, stdout, stdout_tx)
			});

			let stderr_thread = thread::spawn(move || {
				handle_output(StreamTy::Stderr, stderr, stderr_tx)
			});

			let status_thread: thread::JoinHandle<Result<(), InternalError>> = thread::spawn(move || {
				let status_code = child.wait()?;
				status_tx.send(PacketTy::ExitStatus { code: status_code.code() });
				Ok(())
			});


			let outgoing_thread: thread::JoinHandle<Result<(), InternalError>> = thread::spawn(move || {
				loop {
					match outbox_rx.recv() {
						Ok(packet) => {
							let buf = serde_cbor::to_vec(&packet)?;
							erlang_port.write_u16::<NetworkEndian>(buf.len() as u16)?;
							erlang_port.write(&buf)?;
							erlang_port.flush()?;
						},

						Err(msg) => break, 
					}
				}

				Ok(())
			});


		},

		_ => panic!("not yet implemented ..."),
	}

	Ok(())
}


fn handle_output<R: Read>(stream_ty: StreamTy, mut stream: R, outbox: Sender<PacketTy>) -> Result<(), InternalError> {
	'stdout: loop {
		let mut buf = [0u8; 1024];
		let len = stream.read(&mut buf)?;
		if (len == 0) { break 'stdout }

		let packet = PacketTy::DataOut { 
			ty: stream_ty,
			buf: buf[0..len].to_vec() 
		};

		// TODO: log failure 
		if let Err(_msg) = outbox.send(packet) { break 'stdout }
	}

	Ok(())
}

fn dispatch_error(error: InternalError) -> Result<(), InternalError> {
	Ok(())
}

fn main() -> Result<(), InternalError> {

	let mut stdin = io::stdin();
	let mut stdout = io::stdout();

	let mut packet_chain = vec![];

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
		match decode_packets(last_packet_group) {
			Ok(decoded_packet) => dispatch_packet(decoded_packet)?,
			Err(err) => dispatch_error(err)?,
		}

	}
	
	Ok(())
}

// fn read_packet() -> Result<Packet, InternalError> {
// 	let mut stdin = io::stdin();
// 
// 	let mut len_buf = [0u8; 2];
// 	let mut pkt_buf = vec![];
// 
// 	// read length
// 	stdin.read_exact(&mut len_buf)?;
// 	let len = (&len_buf[..]).read_u16::<NativeEndian>()?;
// 	
// 
// 	stdin.read(&mut pkt_buf)?;
// 
// 	unreachable!()
// 
// }
