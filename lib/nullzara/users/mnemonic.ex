defmodule Nullzara.Users.Mnemonic do
  @moduledoc """
  Encodes and decodes 128-bit hex tokens as 12-word BIP39 mnemonic phrases.
  """

  import Bitwise

  @external_resource wordlist_path = Path.join(:code.priv_dir(:nullzara), "bip39/english.txt")

  @words wordlist_path
         |> File.read!()
         |> String.split("\n", trim: true)

  @word_to_index @words |> Enum.with_index() |> Map.new()

  @doc """
  Encodes a 32-character hex token into a 12-word mnemonic phrase.
  """
  def encode(hex_token) when byte_size(hex_token) == 32 do
    {:ok, bits} = Base.decode16(hex_token, case: :mixed)

    bits
    |> :binary.bin_to_list()
    |> Enum.flat_map(fn byte -> for i <- 7..0//-1, do: byte >>> i &&& 1 end)
    |> pad_to(132)
    |> Enum.chunk_every(11)
    |> Enum.map(fn chunk ->
      index = Enum.reduce(chunk, 0, fn bit, acc -> acc * 2 + bit end)
      Enum.at(@words, index)
    end)
    |> Enum.join(" ")
  end

  @doc """
  Decodes a 12-word mnemonic phrase back into a hex token.

  Returns `{:ok, hex_token}` or `{:error, :invalid_length}` or `{:error, :invalid_word}`.
  """
  def decode(phrase) when is_binary(phrase) do
    words = String.split(phrase)
    decode_words(words)
  end

  def decode_words(words) when length(words) != 12, do: {:error, :invalid_length}

  def decode_words(words) do
    with {:ok, indices} <- words_to_indices(words) do
      bits =
        indices
        |> Enum.flat_map(fn index -> for i <- 10..0//-1, do: index >>> i &&& 1 end)
        |> Enum.take(128)

      bytes =
        bits
        |> Enum.chunk_every(8)
        |> Enum.map(fn chunk -> Enum.reduce(chunk, 0, fn bit, acc -> acc * 2 + bit end) end)

      hex = bytes |> :binary.list_to_bin() |> Base.encode16(case: :lower)
      {:ok, hex}
    end
  end

  defp words_to_indices(words) do
    Enum.reduce_while(words, {:ok, []}, fn word, {:ok, acc} ->
      case Map.fetch(@word_to_index, word) do
        {:ok, index} -> {:cont, {:ok, acc ++ [index]}}
        :error -> {:halt, {:error, :invalid_word}}
      end
    end)
  end

  defp pad_to(bits, target) when length(bits) >= target, do: bits
  defp pad_to(bits, target), do: bits ++ List.duplicate(0, target - length(bits))
end
