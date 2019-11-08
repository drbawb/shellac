defmodule Lacca do
  use GenServer
  alias Lacca.Protocol.Encoder
  require Logger

  #
  # API
  #

  @doc """
  Starts a server which will run the executable located at `exec_path`
  with the specified command line arguments. The returned handle, of the form
  `{:ok, pid}`, can be used to interact w/ the program.

  Note that `stdout` and `stderr` from the process are captured inside
  `StringIO` buffers internally. This data will remain in-memory until
  this server is either killed, or the buffers are flushed using the 
  respective API functions.

  ## Errors

  This method will raise `ArgumentError` if the `resin` daemon cannot be
  found on your system's executable `PATH`. The configuration key located
  at `:resin, :daemon_path` can be used to force this process to run the
  daemon from a non-standard location.
  """
  def start(exec_path, args)
  when is_binary(exec_path) and is_list(args) do
    GenServer.start_link(__MODULE__, [path: exec_path, args: args])
  end

  @doc """
  Attempts to terminate the process immediately. Caller should expect that
  the process will not be gracefully terminated; similarly to calling SIGKILL
  on a POSIX operating system.
  """
  def kill(pid) do
    GenServer.call(pid, :kill)
  end


  @doc """
  Returns `{:ok, binary}` which includes any data received from the
  child's `stdout` file descriptor. _Note that the internal buffer is then 
  cleared, such that subsequent reads will not return this same data again._
  """
  def read_stdout(pid) do
    GenServer.call(pid, :read)
  end


  @doc """
  Returns `{:ok, binary}` which includes any data received from the
  child's `stderr` file descriptor. _Note that the internal buffer is then 
  cleared, such that subsequent reads will not return this same data again._
  """
  def read_stderr(pid) do
    GenServer.call(pid, :read_err)
  end

  @doc """
  Returns `:ok` if the data has been sent to the underlying `resin` daemon.
  Note that this function returns immediately after having sent the packet
  to the daemon, no guarantees as to the delivery to the child process are
  afforded. (i.e: the child may have closed its `stdin` prematurely, the child
  may have exited in the interim, it may be deadlocked and not processing stdin,
  etc.)
  """
  def write_stdin(pid, data) when is_binary(data) do
    GenServer.call(pid, {:write, data})
  end


  @doc """
  Requests that the `resin` daemon send `SIGTERM` or equivalent to forcefully
  terminate the running child process. This function returns immediately, and
  the signal is sent asynchronously.

  Use `await/1` if you wish to block on the child process actually terminating.
  """
  def stop_child(pid) do
    {:error, :not_implemented}
  end

  @doc """
  Waits for the child process to exit, and returns a result struct which
  includes the status code (if applicable), and any remaining data from the
  `stdout` or `stderr` buffers for this process.

  When this function returns `pid` will have exited.
  """
  def await(pid) do
    {:error, :not_implemented}
  end

  #
  # Callbacks
  #

  def init(opts) do
    Logger.debug "opening port" 
    {path, _} = Keyword.pop(opts, :path)
    {args, _} = Keyword.pop(opts, :args, [])

    # check we have a valid executable path
    if is_nil(path) or !is_binary(path)  do
      raise ArgumentError, "expected opts[:path] to be a string"
    end

    if is_nil(args) or !is_list(args) do
      raise ArgumentError, "expected opts[:args] to be a list of arguments"
    end

    resin_daemon = Applicaiton.app_dir(:lacca, "priv/resin/resind")

    unless File.exists? resin_daemon do
      raise RuntimeError, "Could not locate `resind` daemon at: #{resin_daemon}"
    end

    # open the port to `resin` daemon
    port  = Port.open({:spawn, resin_daemon}, [:binary, :exit_status, {:packet, 2}])
    p_ref = Port.monitor(port)

    # TODO: negotiate protocol verison
    Encoder.write_start_process(path, args)
    |> Enum.map(fn packet ->
      Logger.debug "sending packet: #{inspect packet}"
      Port.command(port, packet)
    end)

    # open IO streams
    {:ok, p_child_err} = StringIO.open("")
    {:ok, p_child_out} = StringIO.open("")
    {:ok, p_child_in} = StringIO.open("")

    {:ok, %{
      port: port,
      monitor_ref: p_ref,

      child_err: p_child_err,
      child_out: p_child_out,
      child_in:  p_child_in,
    }}
  end

  # reads the currently buffered `stdout` of the child process
  def handle_call(:read, _from, state = %{port: port}) when not is_nil(port) do
    buf = StringIO.flush(state.child_out)
    {:reply, {:ok, buf}, state}
  end

  # reads the currently buffered `stderr` of the child process
  def handle_call(:read_err, _from, state = %{port: port}) when not is_nil(port) do
    buf = StringIO.flush(state.child_err)
    {:reply, {:ok, buf}, state}
  end

  def handle_call({:write, data}, _from, state = %{port: port}) when not is_nil(port) do
    Encoder.write_data_packet(data)
    |> Enum.map(fn packet ->
      Logger.debug "sending packet: #{inspect packet}"
      Port.command(port, packet)
    end)

    {:reply, :ok, state}
  end

  def handle_call(:kill, _from, state = %{port: port}) when not is_nil(port) do
    Encoder.write_exit_packet()
    |> Enum.map(fn packet ->
      Logger.debug "sending packet: #{inspect packet}"
      Port.command(port, packet)
    end)

    {:reply, :ok, state}
  end

  # `resin` daemon exited, RIP us...
  def handle_info({port, {:exit_status, status}}, state) when is_port(port) do
    Logger.info "got exit: #{inspect status}"
    {:noreply, state}
  end

  # handle packet received from `resin` daemon ...
  def handle_info({port, {:data, data}}, state) when is_port(port) do
    decoded_data = CBOR.decode(data)

    case decoded_data do
      {:ok, %{"DataOut" => %{"ty" => "Stdout", "buf" => buf }}, _} ->
        IO.write(state.child_out, buf)

      {:ok, %{"DataOut" => %{"ty" => "Stderr", "buf" => buf}}, _} ->
        IO.write(state.child_err, buf)

      packet ->
        Logger.warn "unhandled data packet: #{inspect packet}"
    end

    {:noreply, state}
  end


  def handle_info({:DOWN, ref, :port, port, reason}, state) when is_port(port) do
    Logger.info "port going down: #{inspect port}"
    Logger.info "got message of port leaving: #{inspect reason}"
    Logger.info "port info: #{inspect Port.info(port)}"
    {:noreply, state}
  end

  def terminate(_reason, state = %{port: port}) when is_port(port) do
    Encoder.write_exit_packet()
    |> Enum.map(fn packet ->
      Logger.debug "sending packet: #{inspect packet}"
      Port.command(port, packet)
    end)
  end

end
