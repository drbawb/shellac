defmodule LaccaTest do
  use ExUnit.Case

  # wait a bit for daemon to settle
  @wait_ms 50

  describe "basic daemon behavior" do
    test "echo client works" do
      # start the echo client & send it a string
      {:ok, pid} = Lacca.start "priv/resin/test_echo", []
      Lacca.write_stdin(pid, "hello, world\n")

      # wait a bit and see if we got echo reply
      :timer.sleep(@wait_ms)
      {:ok, ret_str} = Lacca.read_stdout(pid)
      assert ret_str == "hello, world\n"
    end

    test "stderr client works" do
      # start the echo client & send it a string
      {:ok, pid} = Lacca.start "priv/resin/test_err", []
      Lacca.write_stdin(pid, "hello, world\n")

      # wait a bit and see if we got echo reply
      :timer.sleep(@wait_ms)
      {:ok, ret_str} = Lacca.read_stderr(pid)
      assert ret_str == "hello, world\n"
    end

    test "client hangs up when told to" do
      # star the client and wait for it to be alive
      {:ok, pid} = Lacca.start "priv/resin/test_echo", []
      :timer.sleep(@wait_ms)

      Lacca.kill(pid)
      :timer.sleep(@wait_ms)

      assert not Lacca.alive?(pid)
    end
  end
end
