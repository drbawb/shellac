use byteorder::{ReadBytesExt, WriteBytesExt, NetworkEndian};
use resin::error::InternalError;
use serde::{Deserialize, Serialize};
use std::io::{self, Read, Write};

#[derive(Debug, Deserialize, Serialize)]
enum PacketTy {
	StartProcess { exec: String, args: Vec<String> },

	DataStdin { buf: Vec<u8> },
	DataStdout { buf: Vec<u8> },

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
			// spawn process          (supervisor thread)
			// stdout handler thread  (read from process)
			// stderr handler thread  (read from process)
			// stdin handler thread   (read from erlang)
			// packet handler thread  (collect messages from other threads)
		},

		_ => panic!("not yet implemented ..."),
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
