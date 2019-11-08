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
"\~> 1.3.0" rather than "\~> 1.3" in your build tool. This would allow the patch
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
- (data)	packet specific data (n bytes, CBOR encoded)

### Packet Types

Packet types are as follows:

**TBD**

1. Start Process 	(exec: string, args: [string]])
2. Stop Process 	()
3. DataOut 			(ty: (Stdout | Stderr), buf: [u8])
5. DataIn 			(buf: [u8])

### Future Additions

- POSIX signal support?
- windows support?
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


## TODO

- resin: general clean up of error handling
  - what to do with errors if stdout goes away?
  - logging facilities?

- resin: signal handling architecture
  - need more generalized support for sending processes different kinds of
    signals, not just calling `Child::kill()`

- lacca: handle DataOut packet types

- resin: restructure as state machine?
  - there are bits of the server process state which don't exist until the
    inferior process is running. it would be nice if this was encoded in the
    type system as some kind of FSM so I can stop unwrapping Option<..>
    everywhere.

- multi proc support
  - Should one daemon be able to handle multiple inferior processes?
    I think this is what `erlexec` does but I'm not sure.

