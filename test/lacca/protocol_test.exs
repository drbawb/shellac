defmodule LaccaProtocolTest do
  use ExUnit.Case

  import Lacca.Protocol.BinUtils

  describe "binary manipulation" do
    test "chunking 0-size binary results in empty list" do
      test_bin = <<>>
      list = chunk_binary(test_bin, 1)
      assert list == []
    end

    test "evenly divisible binary chunking produces smallest list" do
      test_bin = <<1,2,3,4,5,6>>
      list = chunk_binary(test_bin, 2)

      assert Enum.count(list) == (6 / 2)
    end

    test "non-evenly divisible chunking doesn't lose remainder" do
      test_bin = <<1,2,3,4,5,6>>
      list = chunk_binary(test_bin, 4)

      assert Enum.count(list) == 2
      assert Enum.at(list, 0) == <<1,2,3,4>>
      assert Enum.at(list, 1) == <<5,6>>
    end

    test "binary smaller than chunk-size results in one element list" do
      test_bin = <<1,2,3,4,5,6>>
      list = chunk_binary(test_bin, 8)
      assert Enum.count(list) == 1
    end


    test "argument error for invalid chunk size (non positive integer)" do
      assert_raise ArgumentError, fn ->
        test_bin = <<1,2,3,4,5,6>>
        _list = chunk_binary(test_bin, 0)
      end

      assert_raise ArgumentError, fn ->
        test_bin = <<1,2,3,4,5,6>>
        _list = chunk_binary(test_bin, -1)
      end
    end
  end
end
