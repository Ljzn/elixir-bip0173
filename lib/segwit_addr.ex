# Copyright (c) 2017 Adán Sánchez de Pedro Crespo
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.

defmodule SegwitAddr do
  import Bitwise

  @moduledoc ~S"""
  Encode and decode BIP-0173 and BIP-0350 compliant SegWit addresses.
  """

  @typedoc """
  Segregated witness program version
  """
  @type segwit_version_t :: 0..16

  @doc ~S"""
  Encode a SegWit address.

  ## Examples

      iex> SegwitAddr.encode("bc", "0014751e76e8199196d454941c45d1b3a323f1433bd6")
      "bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4"

      iex> SegwitAddr.encode("bc", 0, [117, 30, 118, 232, 25, 145, 150, 212,
      ...> 84, 148, 28, 69, 209, 179, 163, 35, 241, 67, 59, 214])
      "bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4"
  """
  @spec encode(String.t(), segwit_version_t, list(byte())) :: String.t()
  def encode(hrp, version, program) when is_list(program) do
    unless version in 0..16 do
      raise ArgumentError, "invalid witness version"
    end

    unless program_length_valid?(version, length(program)) do
      raise ArgumentError, "invalid witness program length"
    end

    encoding = get_encoding(version)
    Bech32.encode(hrp, [version] ++ Bech32.convert_bits(program, 8, 5), encoding)
  end

  @spec encode(String.t(), String.t()) :: String.t()
  def encode(hrp, program) when is_binary(program) do
    <<version, _size, program::binary>> = Base.decode16!(program, case: :mixed)

    program
    |> :binary.bin_to_list()
    |> (&encode(hrp, version, &1)).()
  end

  @doc ~S"""
  Decode a SegWit address.

  ## Examples

      iex> SegwitAddr.decode("bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4")
      {:ok, {"bc", 0, [117, 30, 118, 232, 25, 145, 150, 212,
      84, 148, 28, 69, 209, 179, 163, 35, 241, 67, 59, 214]}}
  """
  @spec decode(String.t()) ::
          {:ok, {String.t(), segwit_version_t, list(byte())}} | {:error, String.t()}
  def decode(addr) do
    case Bech32.decode(addr) do
      {:ok, {hrp, data, encoding}} ->
        case data do
          [version | encoded] when version in 0..16 ->
            program = Bech32.convert_bits(encoded, 5, 8, false)

            cond do
              get_encoding(version) != encoding ->
                {:error, "Invalid encoding for witness version"}

              is_nil(program) or !program_length_valid?(version, length(program)) ->
                {:error, "Invalid program length for witness version"}

              true ->
                {:ok, {hrp, version, program}}
            end

          [_ | _] ->
            {:error, "Invalid witness version"}

          [] ->
            {:error, "Empty data section"}
        end

      error ->
        error
    end
  end

  @doc ~S"""
  Encode a witness program into a hexadecimal ScriptPubKey.

  ## Examples

      iex> SegwitAddr.to_script_pub_key(0, [117, 30, 118, 232, 25, 145, 150,
      ...> 212, 84, 148, 28, 69, 209, 179, 163, 35, 241, 67, 59, 214])
      "0014751e76e8199196d454941c45d1b3a323f1433bd6"
  """
  @spec to_script_pub_key(segwit_version_t, list(byte())) :: String.t()
  def to_script_pub_key(version, program) do
    [
      if version == 0 do
        0
      else
        version + 0x50
      end,
      Enum.count(program) | program
    ]
    |> :binary.list_to_bin()
    |> Base.encode16(case: :lower)
  end

  # Gets encoding for witness version
  defp get_encoding(0), do: :bech32
  defp get_encoding(v) when v in 1..16, do: :bech32m

  # Validates witness program length
  # BIP-0141 defines witness program length must be between 2 and 40 inclusive
  # for witness version 0 only 20 and 32 are allowed
  # BIP-0341 specifies version 1 and length 32 but does not introduce any limits
  # future BIPs may introduce other requirements
  defp program_length_valid?(0, length) when length in [20, 32], do: true
  defp program_length_valid?(version, length) when version != 0 and length in 2..40, do: true
  defp program_length_valid?(_, _), do: false
end
