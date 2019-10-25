# shellac

`shellac` is a suite of software which aims to provides OS-level 
process control for the Elixir language. The software is composed of two
sub-projects which coordinate to accomplish this goal:

- `lacca`: an Elixir process control library, implemented as
  an OTP application which can be included in a `mix` project.

- `resin`: a Rust binary which acts as a companion to the `lacca`
  OTP application. This binary provides process control and 
  supervision, it also multiplexes the processes open file descriptors
  onto the single BEAM port.


## Build Instructions

Please see the `README` of each respective project for detailed
build instructions. Note that `resin` will need to aditionally
be installed on the system `PATH` in order for `lacca` to use it.

## Protocol Versioning

The `lacca` and `resin` programs *do not* follow standard semantic versioning
guideliens. Please read the following to understand how the project's versions
are controlled. *The developer's suggest pinning both a major AND minor version*
when using build tools which expect semantic versioning. i.e: pin to
"~> 1.3.0" rather than "~> 1.3" in your build tool. This would allow the patch
version to change, but not the major or minor version.

The version number consits of `protocol`, `library`, and `patch` components.
Their significance to the project is as follows:

- `protocol` will whenever the protocol between `lacca` and `resin` are
  changed in non-backwards compatible ways. Newer major versions of `resin` 
  will work with older versions of `lacca`, but not vice versa.

- `minor` will be changed to reflect *breaking changes* to the program's API.
  - Such changes for `lacca` might include:
    - Removed functions
    - Change of non-optional arguments to a function
    - Change in return value from a function

  - Such changes to `resin` might include:
    - Command line options renamed or removed
    - Change in interpretation of command line arguments

- `patch` will be changed when backwards-compatible changes are introduced
  to either the protocol, library, or daemon.

NOTE: `v0` of the protocol is considered unstable. For best results 
you should always build and deploy the `v0` programs together.

## Protocol Format

`shellac` v0 packets are sent on the wire as follows:

- (n) 		two bytes identifying packet length
- (ty) 		one byte identifying packet flags & type
- (data)	packet specific data (n-1 bytes)


NOTE: The upper 4-bits (i.e: `0xF0 & <ty>`) are reserved for flags.
      Packet types are only inclusive of the lower 4-bits.

The MSB of the `ty` byte is considered a cotinuation bit, its presence
indicates the receiver should expect that additional packets (of the same type)
will be forthcoming. The last packet of any given message should have the
continuation bit set to `0`.

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


### Future Additions

- POSIX signal support?
- Standard stream redirection?
- Buffered input mode?

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


