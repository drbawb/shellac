defmodule Lacca do
  use GenServer
  require Logger

  def foo(n, state \\ "") when n > 0, do: foo(n-1, state <> <<0>>)
  def foo(n, state), do: state

  def test do
    {:ok, pid} = GenServer.start_link(Lacca, [])
    :ok = GenServer.call(pid, :test)
    pid
  end

  def init(opts \\ []) do
    {:ok, %{port: nil}}
  end

  def handle_call(:test, _from, state) do
    Logger.info "opening port ..."
    port = Port.open({:spawn, "../resin/target/debug/resin"}, [:binary, {:packet, 2}])
    _ref = Port.monitor(port)

    Logger.info "sending command ..."
    Port.command(port, "hello\n")

    {:reply, :ok, %{state | port: port}} 
  end

  def handle_call({:send, data}, _from, state = %{port: port}) when not is_nil(port) do
    Port.command(port, data)
    {:reply, :ok, state}
  end

  def handle_info({port, {:data, data}}, state) do
    Logger.info "got data: #{inspect data}"
    {:noreply, state}
  end

  def handle_info({:DOWN, ref, :port, port, reason}, state) do
    Logger.info "got message of port leaving: #{inspect reason}"
    {:noreply, state}
  end
end
