# shellac

`shellac` is a suite of software which  OS-level process control
for the Elixir language. The suite is composed of two tools:

- `lacca`: the Elixir process control library, implemented as
  an OTP application which can be included in a `mix` project.

- `resin`: a Rust binary which acts as a companion to the `lacca`
  OTP application. This binary provides process supervision, it
  also multiplexes the processes open file descriptors onto the
  single BEAM port.


## Build Instructions

Please see the `README` of each respective project for detailed
build instructions. Note that `resin` will need to aditionally
be installed on the system `PATH` in order for `lacca` to use it.

## Protocol Overview

The `resin` v1 protocol is described below.


`resin` packets are sent on the wire as follows:

- (n) 		two bytes identifying packet length
- (ty) 		one byte identifying packet type
- (data)	packet specific data (n-1 bytes)


NOTE: the MSB of the `ty` byte is a continuation bit.
If it is set to `1` the receiver should expect that additional packets
(of the same type) will be forthcoming. The last packet of any given
message should have the continuation bit set to `0`.

NOTE: the terms `rx (receive)` and `tx (transmit)` below are from the
perspective of the `resin` process. `resin` is receiving data *from*
the Erlang VM (to be sent to the child process), and it is transmitting
data *to* the Erlang VM (which it has read from the child process.)

Packet types are as follows:

- HandshakeReqV1 { version: u8 } 
  - Begins a session using major version 1, and the specified minor version.
  - `resin` servers *should* be able to speak previous protocol revisions.

- HandshakeRepV1 { ok: bool } 

- SetupProcess { executable: [u8,...], args: [[u8, ...], ...], opts: TBD }

- Stream { fd: u8, data: [u8, ...] }
  - When *receiving* this packet from the Erlang VM it will be buffered
    and then sent to the child process on the specified descriptor.

  - When *sending* this packet to the Erlang VM it represents data
    read from the child process on the specified file descriptor.


- Terminate { timeout: u8 }
  - Instructs all readers and writers to close immediately.
    NOTE: incomplete packets will be discarded, but packets which were
    on the in-flight transmission queue *may* still be sent.

  - Attempts to kill the process.
    - On Unix-like systems this will send `SIGTERM`, wait `timeout` seconds, and
      then send the equivalent of `SIGKILL`.

- TerminateRep { TBD }
  - should return an error code and (if applicable) program exit status
  - states are as follows:
    - program exited (sucesfully|failed)
    - program exited (before|after) timeout


### Future Protocol Additions

- POSIX signal support?


## Lacca Design

When the `lacca` application starts it will kick off a supervision
process. To start an OS-level process `lacca` will perform the
following initialization sequence:

- Start a child BEAM process w/ the given command line.

- Open a port to a `resin` daemon in `:binary` mode.

- Handshake w/ the `resin` daemon to verify matching protocol versions.

- Pass the initialization arguments to the `resin` daemon.

- Enter a message loop awaiting messages from the port, as well
  as messages from other peers in the Erlang VM.

This process may receive the following messages:

- `(rx_pkt, fd, [u8 ...])` <- received to stdout or stderr
- `(tx_pkt, fd, [u8 ...])` -> sent to stdin


