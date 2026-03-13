defmodule Nullzara.Users.MnemonicTest do
  use ExUnit.Case, async: true

  alias Nullzara.Users.Mnemonic

  describe "encode/1" do
    test "produces 12 words from a 32-char hex token" do
      token = "00000000000000000000000000000000"
      phrase = Mnemonic.encode(token)
      words = String.split(phrase)
      assert length(words) == 12
    end

    test "produces different phrases for different tokens" do
      phrase1 = Mnemonic.encode("aaaabbbbccccddddeeeeffffaaaabbbb")
      phrase2 = Mnemonic.encode("11112222333344445555666677778888")
      refute phrase1 == phrase2
    end
  end

  describe "decode/1 and decode_words/1" do
    test "round-trips a hex token through encode/decode" do
      token = Base.encode16(:crypto.strong_rand_bytes(16), case: :lower)
      phrase = Mnemonic.encode(token)
      assert {:ok, ^token} = Mnemonic.decode(phrase)
    end

    test "round-trips multiple random tokens" do
      for _ <- 1..10 do
        token = Base.encode16(:crypto.strong_rand_bytes(16), case: :lower)
        phrase = Mnemonic.encode(token)
        assert {:ok, ^token} = Mnemonic.decode(phrase)
      end
    end

    test "returns error for wrong word count" do
      assert {:error, :invalid_length} = Mnemonic.decode("one two three")
    end

    test "returns error for invalid word" do
      words = List.duplicate("abandon", 11) ++ ["notaword"]
      assert {:error, :invalid_word} = Mnemonic.decode_words(words)
    end

    test "decodes all-zeros token correctly" do
      token = "00000000000000000000000000000000"
      phrase = Mnemonic.encode(token)
      assert {:ok, ^token} = Mnemonic.decode(phrase)
    end

    test "decodes max token correctly" do
      token = "ffffffffffffffffffffffffffffffff"
      phrase = Mnemonic.encode(token)
      assert {:ok, ^token} = Mnemonic.decode(phrase)
    end
  end
end
