# Project `shellac` Change Log

The following is a list of official `shellac` releases, in reverse
chronological order. These notes include both the client API (`lacca`)
as well as the daemon process (`resin`), as they are versioned together.


## Version: 0.1.0

Initial release. This includes the following core functionality:

- `mix.exs` is setup to build this as a package suitable for inclusion
  from the `hex.pm` package repository

- `mix compile` is able to build the requisite `resin` daemon and include
  it in the `priv/` directory of the `lacca` OTP application.

- `lacca` core API allows for:
  - starting a process (by relative or absolute path) w/ arguments.
  - terminating a process (`SIGKILL` effectively)
  - polling for `stdout` / `stderr` which are internally buffered
  - writing to `stdin`
