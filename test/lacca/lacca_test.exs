defmodule LaccaTest do
  use ExUnit.Case

  # wait a bit for daemon to settle
  @wait_ms 250

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
  end
end
