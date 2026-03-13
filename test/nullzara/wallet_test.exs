defmodule Nullzara.WalletTest do
  use Nullzara.DataCase, async: true

  alias Nullzara.Wallet

  describe "generate_nonce/0" do
    test "returns a 64-character hex string" do
      nonce = Wallet.generate_nonce()
      assert byte_size(nonce) == 64
      assert Regex.match?(~r/\A[0-9a-f]{64}\z/, nonce)
    end

    test "returns unique values" do
      nonce1 = Wallet.generate_nonce()
      nonce2 = Wallet.generate_nonce()
      refute nonce1 == nonce2
    end
  end

  describe "build_sign_message/1" do
    test "wraps nonce in human-readable message" do
      message = Wallet.build_sign_message("abc123")
      assert message == "Sign in to Nullzara\n\nNonce: abc123"
    end
  end

  describe "verify_signature/3" do
    test "recovers correct address from a valid signature" do
      # Generate a test keypair
      private_key = :crypto.strong_rand_bytes(32)
      {:ok, public_key} = ExSecp256k1.create_public_key(private_key)

      # Derive Ethereum address from public key
      # public_key is 65 bytes (0x04 prefix + 64 bytes), strip prefix
      <<4, key_data::binary-size(64)>> = public_key
      <<_::binary-size(12), address_bytes::binary-size(20)>> = ExKeccak.hash_256(key_data)
      expected_address = "0x" <> Base.encode16(address_bytes, case: :lower)

      # Build and sign message
      nonce = Wallet.generate_nonce()
      message = Wallet.build_sign_message(nonce)

      # EIP-191 prefix
      prefixed = "\x19Ethereum Signed Message:\n#{byte_size(message)}" <> message
      hash = ExKeccak.hash_256(prefixed)

      {:ok, {r, s, v}} = ExSecp256k1.sign(hash, private_key)

      # Reconstruct 65-byte signature as MetaMask would return it (r + s + v)
      signature = r <> s <> <<v + 27>>
      hex_signature = "0x" <> Base.encode16(signature, case: :lower)

      assert {:ok, recovered} = Wallet.verify_signature(hex_signature, message, expected_address)
      assert String.downcase(recovered) == String.downcase(expected_address)
    end

    test "rejects signature from wrong address" do
      private_key = :crypto.strong_rand_bytes(32)

      nonce = Wallet.generate_nonce()
      message = Wallet.build_sign_message(nonce)

      prefixed = "\x19Ethereum Signed Message:\n#{byte_size(message)}" <> message
      hash = ExKeccak.hash_256(prefixed)

      {:ok, {r, s, v}} = ExSecp256k1.sign(hash, private_key)

      signature = r <> s <> <<v + 27>>
      hex_signature = "0x" <> Base.encode16(signature, case: :lower)

      assert {:error, :address_mismatch} =
               Wallet.verify_signature(
                 hex_signature,
                 message,
                 "0x0000000000000000000000000000000000000000"
               )
    end
  end

  describe "store_credential/1" do
    test "creates a user and wallet credential" do
      address = "0x" <> Base.encode16(:crypto.strong_rand_bytes(20), case: :lower)

      assert {:ok, user, credential} = Wallet.store_credential(address)
      assert user.name == "Anonymous"
      assert user.mnemonic_hash != nil
      assert user.token_hash != nil
      assert credential.address == String.downcase(address)
      assert credential.user_id == user.id
    end
  end

  describe "get_credential_by_address/1" do
    test "returns credential with preloaded user" do
      address = "0x" <> Base.encode16(:crypto.strong_rand_bytes(20), case: :lower)
      {:ok, _user, _credential} = Wallet.store_credential(address)

      assert {:ok, found} = Wallet.get_credential_by_address(address)
      assert found.address == String.downcase(address)
      assert %Nullzara.Users.User{} = found.user
    end

    test "returns error for unknown address" do
      assert {:error, :not_found} =
               Wallet.get_credential_by_address("0x0000000000000000000000000000000000000000")
    end
  end

  describe "attach_credential/2" do
    test "attaches wallet to existing user" do
      {:ok, user} = Nullzara.Users.create_user_with_token(%{name: "Test"})
      address = "0x" <> Base.encode16(:crypto.strong_rand_bytes(20), case: :lower)

      assert {:ok, credential} = Wallet.attach_credential(user, address)
      assert credential.user_id == user.id
      assert credential.address == String.downcase(address)
    end

    test "returns error if user already has a wallet" do
      address1 = "0x" <> Base.encode16(:crypto.strong_rand_bytes(20), case: :lower)
      {:ok, user, _cred} = Wallet.store_credential(address1)

      address2 = "0x" <> Base.encode16(:crypto.strong_rand_bytes(20), case: :lower)
      assert {:error, _changeset} = Wallet.attach_credential(user, address2)
    end
  end

  describe "detach_credential/1" do
    test "removes wallet credential" do
      address = "0x" <> Base.encode16(:crypto.strong_rand_bytes(20), case: :lower)
      {:ok, _user, credential} = Wallet.store_credential(address)

      assert {:ok, _} = Wallet.detach_credential(credential)
      assert {:error, :not_found} = Wallet.get_credential_by_address(address)
    end
  end
end
