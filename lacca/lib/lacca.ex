defmodule Lacca do
  use GenServer
  alias Lacca.Protocol.Encoder
  require Logger

  @resin_daemon "../resin/target/debug/resin"

  #
  # API
  #

  def test do
    Logger.info "starting OS process ..."
    path = "../resin/target/debug/test_child"

    {:ok, pid} = GenServer.start_link(__MODULE__, [path: path, args: ["fuck"]])
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

    # open the port to `resin` daemon
    port  = Port.open({:spawn, @resin_daemon}, [:binary, :exit_status, {:packet, 2}])
    p_ref = Port.monitor(port)

    # TODO: negotiate protocol verison
    Encoder.write_start_process(path, args)
    |> Enum.map(fn packet ->
      Logger.debug "sending packet: #{inspect packet}"
      Port.command(port, packet)
    end)

    {:ok, %{port: port, monitor_ref: p_ref }}
  end

  def handle_call({:send, data}, _from, state = %{port: port}) when not is_nil(port) do
    Port.command(port, data)
    {:reply, :ok, state}
  end

  def handle_info({port, {:exit_status, status}}, state) do
    Logger.info "got exit: #{inspect status}"
    {:noreply, state}
  end

  def handle_info({port, {:data, data}}, state) do
    Logger.info "got data: #{inspect data}"
    {:noreply, state}
  end

  def handle_info({:DOWN, ref, :port, port, reason}, state) do
    Logger.info "port going down: #{inspect port}"
    Logger.info "got message of port leaving: #{inspect reason}"
    Logger.info "port info: #{inspect Port.info(port)}"
    {:noreply, state}
  end
end
