# shellac

[![builds.sr.ht status](https://builds.sr.ht/~hime/shellac.svg)](https://builds.sr.ht/~hime/shellac?)

`shellac` is a suite of software which aims to provides OS-level 
process control for the Elixir language. The software is composed of two
sub-projects which coordinate to accomplish this goal:

- `lacca`: an Elixir process control library, implemented as
  an OTP application which can be included in a `mix` project.

- `resin`: a Rust binary which acts as a companion to the `lacca`
  OTP application. This binary provides process control and 
  supervision, it also multiplexes the process's open file descriptors
  onto the single BEAM port.


## Prerequisites

You will need a Rust toolchain, which includes the build tool `cargo`, in
order to sucesfully build this package. Please visit the Rust website for
[instructions on how to install][rust-install] these tools. This library
can be built with the "stable channel" of the Rust compiler.

[rust-install]: https://www.rust-lang.org/tools/install

## Getting Started

1. Add `{:lacca, "~> 0.1"}` to your `mix.exs` file's dependencies.
2. Run `mix deps.get` to download the dependency.
3. Run `mix deps.compile` to verify that the package compiles sucessfully.
4. Use the library in your program, for instance ...

```elixir
{:ok, pid} = Lacca.start "echo", ["hello, world."]
Lacca.read_stdout pid
# {:ok, "hello, world.\n"}
Lacca.stop pid
```

### Note on Native Code 

This library builds a native executable which is bundled into the `priv/`
directory of this OTP application during the `mix compile` phase. To do
this you must have a working Rust toolchain installed on any machine that
will be compiling a project that depends on `lacca`. You *do not* need the
toolchain installed on deployment targets, however when building a release,
e.g: with the `mix release` command, you will need to ensure that the resulting
binaries can be executed on the target system.

Some common gotchas include:

- Building on Mac OS (mach) & deploying on Linux (ELF), etc.
- Building on an x64 (64-bit) architecture and deploying on i686 (32-bit).
- On Windows: Rust has two toolchains, GNU and MSVC, so care should be taken
  to choose the correct one for your environment.

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
  - wtf do we do on Windows land?

- resin: restructure as state machine?
  - there are bits of the server process state which don't exist until the
    inferior process is running. it would be nice if this was encoded in the
    type system as some kind of FSM so I can stop unwrapping Option<..>
    everywhere.

- resin: multi proc support
  - Should one daemon be able to handle multiple inferior processes?
    I think this is what `erlexec` does but I'm not sure.

  - Not sure this is actually desirable; reduces fault isolation, removes
    1:1 mapping of erlang process -> os process which makes it harder to
    structure OTP applications. there are arguments to be made about resource
    efficiency though (less vm ports/memory/CPU/file descriptors used, et al.)


- lacca: explore stdout/stderr API design space
  - with streams how do we signal EOF? (separate packet type?)
  - what if user wants to stream by line?
  - should we send messages to interested processes instead of a
    buffer that is read-once? (`flush()` destroys the contents of the
    buffer...)

- shellac: lightweight protocol
  - once the protocol is relatively stable I'd like to design a custom
    wire format. we have pretty straightforward types (integer sizes, byte lists)
    and CBOR seems to have a fair bit of overhead since rust enums get encoded
    as dictionaries.

  - this will be a major breaking change so probably do it before 1.0

- shellac: error reporting
  - internally resin has multiple threads coordinating to manage the process.
    this means that currently a request, and errors resulting from that request,
    happen asynchronously.

    - for e.g: resin accepts input, passes input to the child, and then encounters
      an error. -- the client process has already moved on, since it sucesfully wrote
      the data to the port.

  - only way I can see to fix this is to either enforce synchrony, or have the client
    provide a coorleation ID for errors. (basically tag each requests with a unique ID)

  - that raises the question of what do we use for request IDs, how do we serialize it
    on the wire, is it part of packet header or packet itself? etc...
