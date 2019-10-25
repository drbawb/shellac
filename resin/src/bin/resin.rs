use byteorder::{ReadBytesExt, WriteBytesExt, NetworkEndian};
use resin::error::InternalError;
use std::io::{self, Cursor, Read, Write};

fn main() -> Result<(), failure::Error> {

	let mut stdin = io::stdin();
	let mut stdout = io::stdout();


	'header: loop {
		// read packet
		let mut len_buf = [0u8; 2];
		let size = stdin.read(&mut len_buf)?;

		if size == 0 { break 'header }

		assert_eq!(len_buf.len(), size);
		let packet_len = (&len_buf[..]).read_u16::<NetworkEndian>()?;

		let mut packet = vec![0u8; packet_len as usize];
		stdin.read_exact(&mut packet)?;

		// echo length to client
		stdout.write_u16::<NetworkEndian>(2)?;
		stdout.write_u16::<NetworkEndian>(packet_len)?;
		stdout.flush()?;

		// stdout.write(&[2])?;
		// stdout.write(&len[0..2])?;
		// stdout.flush()?;
	}
	


	// generate error
	// let err = Packet::Error { err: "expected start packet".to_string() };
	// let mut buf = vec![];
	// serde_cbor::to_writer(&mut buf, &err)?;

	// assert!(buf.len() <= 0xFFFF);
	// let buf_len_u16 = buf.len() as u16;
	// let buf_len_hi = ((buf_len_u16 & 0xFF00) >> 8) as u8;
	// let buf_len_lo = (buf_len_u16 & 0x00FF) as u8;

	// stdout.write(&[buf_len_hi, buf_len_lo])?;
	// stdout.write(&buf)?;
	// stdout.flush()?;

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
