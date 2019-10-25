defmodule Lacca.Protocol do
  @moduledoc """
  This module provides helper functions for communicating with external
  processes which implement the `shellac` protocol. The wire format of
  the protocol follows:

  - u16       packet length (i.e: read next `n` bytes)
  - u8        packet flags & type
  - [u8,...]  packet payload 

  NOTE: if the high bit (0x80) of the packet flags are set this message
  is *incomplete* and the payload must be buffered by the receiver.
  """

  defmodule Const do
    def version, do: 1

    def handshake_req, do: 0x00
    def handshake_rep, do: 0x01

    def start_process, do: 0x02
    def stop_process,  do: 0x03
  end

  defmodule BinUtils do
    @moduledoc """
    A collection of useful transformations when working w/ the
    binary portions of this protocol.
    """

    @doc "Splits a large binary into a list of smaller `chunk_size` binaries."
    def chunk_binary(bin, chunk_size) 
    when is_integer(chunk_size) and is_binary(bin) and chunk_size > 0
    do
      _chunk_helper(bin, chunk_size, [])
      |> Enum.reverse()
    end

    def chunk_binary(_bin, _chunk_size) do
      raise ArgumentError, "chunk size must be greater than zero"
    end

    defp _chunk_helper(<<>>, _chunk_size, acc), do: acc
    defp _chunk_helper(bin, chunk_size, acc) do
      case bin do
        << head::binary-size(chunk_size), rest::binary >>  ->
          _chunk_helper(rest, chunk_size, [head | acc])

        << rest::binary >> ->
          _chunk_helper(<<>>, chunk_size, [rest | acc])
      end
    end
  end


  defmodule Encoder do
    import Bitwise
    import Const

    # 16-bits less `length` and `flags`
    @max_payload_size (0xFFFF - 0x02 - 0x01)


    defp _serialize_packets(packets, type) do
      _serialize_packets(packets, type, [])
    end

    defp _serialize_packets([], _type, acc) do
      Enum.reverse(acc)
    end

    defp _serialize_packets([head | []], type, acc) do
      packet = _write_packet(_encode_flags(type, false), head)
      _serialize_packets([], type, [packet | acc])
    end

    defp _serialize_packets([head | tail], type, acc) do
      packet = _write_packet(_encode_flags(type, true), head)
      _serialize_packets(tail, type, [packet | acc])
    end

    defp _encode_flags(type, is_continuation \\ false) when is_integer(type) do
      case is_continuation do
        true  -> bor(0x80, band(0x0F, type))
        false -> band(0x0F, type)
      end
    end

    defp _write_packet(flags, payload) when is_binary(payload) do
      payload_len = String.length(payload) + 1
      << <<payload_len::16>>, flags >>  <> payload
    end

    def write_handshake_req() do
      <<0, 2, _encode_flags(handshake_req()), version()>> 
    end

    def write_start_process(exec_name, args \\ []) do
      start_process_packet = %{
        "StartProcess" => %{
          "executable" => exec_name,
          "arguments"  => args
        }
      }


      packet_bin = CBOR.encode(start_process_packet)
      packet_list = BinUtils.chunk_binary(packet_bin, @max_payload_size)
                    |> _serialize_packets(start_process())


    end
  end

end
