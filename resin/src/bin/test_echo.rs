use std::io::{self, Write};

fn main() {
	loop {
		let mut buf = String::new();
		io::stdin().read_line(&mut buf)
			.expect("could not read line");

		if buf.starts_with("exit") {
			std::process::exit(0);
		}

		io::stdout().write(&buf.as_bytes())
			.expect("could not write line");
	}
}
