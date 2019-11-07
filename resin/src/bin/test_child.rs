use std::{time, thread};

fn main() {
	let mut i = 0;
	loop {
		println!("hello world");
		thread::sleep(time::Duration::from_secs(5));

		i += 1;
		if i > 3 { std::process::exit(42) }

	}
}
