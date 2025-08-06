defmodule Lacca do
  use GenServer
  alias Lacca.Protocol.Encoder
  require Logger

  #
  # API
  #

  @spec start(String.t(), list(String.t())) :: GenServer.on_start()
  @doc """
  Starts the Lacca client without linking it to the caller's process.

  See `start_link/2` for more information.
  """
  def start(exec_path, args) do
    GenServer.start(__MODULE__, [path: exec_path, args: args])
  end


  @spec start_link(String.t(), list(String.t())) :: GenServer.on_start()
  @doc """
  Starts a Lacca client process which will run the executable located at
  `exec_path` with the specified command line arguments. The returned handle,
  of the form `{:ok, pid}`.

  The `pid` represents the `lacca` client, which communicates w/ a `resin`
  daemon via an external `Port`. The program at `exec_path` is supervised
  by this `resin` daemon, and is referred to as the `inferior` process.

  Note that `stdout` and `stderr` from the process are captured inside
  `StringIO` buffers internally. This data will remain in-memory until
  this server is either stopped, or the buffers are flushed using the 
  respective API functions: `read_stdout/1` and `read_stderr/1`.


  ## Errors

  This method will raise `ArgumentError` if the `resin` daemon cannot be
  found on your system's executable `PATH`. The configuration key located
  at `:resin, :daemon_path` can be used to force this process to run the
  daemon from a non-standard location.
  """
  def start_link(exec_path, args)
  when is_binary(exec_path) and is_list(args) do
    GenServer.start_link(__MODULE__, [path: exec_path, args: args])
  end

  @spec stop(pid()) :: :ok
  @doc """
  Shuts down the Lacca client process and closes the underlying `resin` port.

  Note that `resin` *will not* ask the child process to terminate when shutting down.
  Calling this, without calling `kill/1` et al. first, is essentially the same as
  just closing the `stdin` of the inferior process.

  In the case that the inferior process does not exit upon reading EOF from
  stdin it will continue running unsupervised in the background. If you need to
  guarantee that the inferior process does not continue running: you *must* call
  `kill/1`, or similar, and wait for `alive?/1` to return `false` before stopping
  the Lacca client.
  """
  def stop(pid) do
    GenServer.stop(pid)
  end

  @spec alive?(pid()) :: boolean()
  @doc """
  Returns `true` if the inferior process is alive, otherwise returns `false`.
  """
  def alive?(pid) do
    GenServer.call(pid, :is_alive)
  end

  @spec status(pid()) :: integer()
  @doc """
  Returns the exit status as an integer if the process has exited and one was
  provided, otherwise returns `nil`.
  """
  def status(pid) do
    GenServer.call(pid, :exit_status) 
  end

  @spec kill(pid()) :: :ok | {:error, String.t()}
  @doc """
  Attempts to terminate the process immediately. Caller should expect that
  the process will not be gracefully terminated; similarly to calling SIGKILL
  on a POSIX operating system.
  """
  def kill(pid) do
    GenServer.call(pid, :kill)
  end

  @spec read_stdout(pid()) :: {:ok, String.t()}
  @doc """
  Returns `{:ok, binary}` which includes any data received from the
  child's `stdout` file descriptor. _Note that the internal buffer is then 
  cleared, such that subsequent reads will not return this same data again._
  """
  def read_stdout(pid) do
    GenServer.call(pid, :read)
  end

  @spec read_stderr(pid()) :: {:ok, String.t()}
  @doc """
  Returns `{:ok, binary}` which includes any data received from the
  child's `stderr` file descriptor. _Note that the internal buffer is then 
  cleared, such that subsequent reads will not return this same data again._
  """
  def read_stderr(pid) do
    GenServer.call(pid, :read_err)
  end

  @spec write_stdin(pid(), String.t()) :: :ok | {:error, String.t()}
  @doc """
  Returns `:ok` once the data has been sent to the underlying `resin` daemon.

  Note that this function returns immediately after having sent the packet
  to the daemon, no guarantees as to the delivery to the child process are
  afforded. (i.e: the child may have closed its `stdin` prematurely, the child
  may have exited in the interim, it may be deadlocked and not processing stdin,
  etc.)
  """
  def write_stdin(pid, data) when is_binary(data) do
    GenServer.call(pid, {:write, data})
  end

  #
  # Callbacks
  #

  @doc false
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

    resin_daemon = Application.app_dir(:lacca, "priv/resin/resind")

    unless File.exists? resin_daemon do
      raise RuntimeError, "Could not locate `resind` daemon at: #{resin_daemon}"
    end

    # open the port to `resin` daemon
    port  = Port.open({:spawn, resin_daemon}, [:binary, :exit_status, {:packet, 2}])
    p_ref = Port.monitor(port)

    # TODO: negotiate protocol verison
    Encoder.write_start_process(path, args)
    |> Enum.map(fn packet ->
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

      is_alive: true,
      exit_status: nil,
    }}
  end

  @doc false
  def handle_call(:is_alive, _from, state) do
    # check if the port is still open
    {:reply, state.is_alive, state}
  end

  @doc false
  def handle_call(:exit_status, _from, state) do
    {:reply, Map.get(state, :exit_status), state}
  end

  @doc false
  def handle_call(:read, _from, state = %{port: port}) when not is_nil(port) do
    # reads the currently buffered `stdout` of the child process
    buf = StringIO.flush(state.child_out)
    {:reply, {:ok, buf}, state}
  end

  @doc false
  def handle_call(:read_err, _from, state = %{port: port}) when not is_nil(port) do
    # reads the currently buffered `stderr` of the child process
    buf = StringIO.flush(state.child_err)
    {:reply, {:ok, buf}, state}
  end

  @doc false
  def handle_call({:write, data}, _from, state = %{port: port}) when not is_nil(port) do
    # writes some data to the `resin` port
    Encoder.write_data_packet(data)
    |> Enum.map(fn packet ->
      Port.command(port, packet)
    end)

    {:reply, :ok, state}
  end

  @doc false
  def handle_call(:kill, _from, state = %{port: port}) when not is_nil(port) do
    # tell inferior process it's time *to die.*
    Encoder.write_exit_packet()
    |> Enum.map(fn packet ->
      Port.command(port, packet)
    end)

    {:reply, :ok, state}
  end

  @doc false
  def handle_info({port, {:exit_status, status}}, state) when is_port(port) do
    # `resin` daemon exited, RIP us...
    Logger.debug "resin daemon hung-up w/ code: #{status}"
    {:noreply, state}
  end

  @doc false
  def handle_info({port, {:data, data}}, state) when is_port(port) do
    # handle packet received from `resin` daemon ...
    decoded_data = Msgpax.unpack(data)

    case decoded_data do
      {:ok, %{"DataOut" => %{"ty" => "Stdout", "buf" => buf}}} ->
        IO.write(state.child_out, buf)
        {:noreply, state}

      {:ok, %{"DataOut" => %{"ty" => "Stderr", "buf" => buf}}} ->
        IO.write(state.child_err, buf)
        {:noreply, state}

      {:ok, %{"ExitStatus" => %{"code" => code}}} ->
        Port.close(state.port)
        Logger.debug "apply status: #{inspect code}"
        {:noreply, %{state | exit_status: code}}

      packet ->
        Logger.warning "unhandled data packet: #{inspect packet}"
        {:noreply, state}
    end

  end

  @doc false
  def handle_info({:DOWN, _ref, :port, port, reason}, state) when is_port(port) do
    # handle the `resin` port hanging up ...
    Logger.debug "port going down: #{inspect port}"
    Logger.debug "got message of port leaving: #{inspect reason}"
    Logger.debug "port info: #{inspect Port.info(port)}"

    {:noreply, %{state | is_alive: false}}
  end

  @doc false
  def terminate(_reason, state) do
    # if the port is alive: at least *try* to shut `resin` down cleanly.
    unless is_nil(state.port) do
      Encoder.write_exit_packet()
      |> Enum.map(fn packet ->
        Port.command(state.port, packet)
      end)

      {:ok, :port_shutdown}

    end
  end
end
