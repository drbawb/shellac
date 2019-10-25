use std::{time, thread};

fn main() {
	loop {
		println!("hello world");
		thread::sleep(time::Duration::from_secs(5));
	}
}
