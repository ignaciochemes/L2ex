defmodule L2E.Packet.Client.RequestMakeMacro do
  @moduledoc "Opcode 0xC1 — client sends a new macro to save."
  defstruct [:macro_id, :name, :descr, :keybind, :icon, :commands]

  def decode(<<macro_id::little-32, rest::binary>>) do
    with {:ok, name, r1} <- read_utf16le_str(rest),
         {:ok, descr, r2} <- read_utf16le_str(r1),
         {:ok, keybind, r3} <- read_utf16le_str(r2),
         <<icon::8, cmd_count::8, _rest2::binary>> <- r3 do
      {:ok,
       %__MODULE__{
         macro_id: macro_id,
         name: name,
         descr: descr,
         keybind: keybind,
         icon: icon,
         commands: "count:#{cmd_count}"
       }}
    else
      _ -> {:error, :invalid}
    end
  end

  def decode(_), do: {:error, :invalid}

  defp read_utf16le_str(<<len::little-16, rest::binary>>) when byte_size(rest) >= len * 2 do
    byte_len = len * 2
    <<chars::binary-size(byte_len), tail::binary>> = rest
    str = :unicode.characters_to_binary(chars, {:utf16, :little}, :utf8)
    {:ok, str, tail}
  end

  defp read_utf16le_str(_), do: :error
end
