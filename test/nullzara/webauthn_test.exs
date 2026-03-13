defmodule Nullzara.WebauthnTest do
  use Nullzara.DataCase, async: true

  alias Nullzara.Webauthn

  describe "generate_registration_challenge/0" do
    test "returns a Wax.Challenge struct" do
      challenge = Webauthn.generate_registration_challenge()
      assert %Wax.Challenge{} = challenge
    end
  end

  describe "generate_authentication_challenge/0" do
    test "returns a Wax.Challenge struct" do
      challenge = Webauthn.generate_authentication_challenge()
      assert %Wax.Challenge{} = challenge
    end
  end

  describe "store_credential/3" do
    test "creates a user and credential record" do
      credential_id = :crypto.strong_rand_bytes(32)

      cose_key = %{
        1 => 2,
        3 => -7,
        -1 => 1,
        -2 => :crypto.strong_rand_bytes(32),
        -3 => :crypto.strong_rand_bytes(32)
      }

      assert {:ok, user, credential} = Webauthn.store_credential(credential_id, cose_key, 0)
      assert user.name == "Anonymous"
      assert user.mnemonic_hash != nil
      assert user.token_hash != nil
      assert credential.credential_id == credential_id
      assert credential.sign_count == 0
      assert credential.user_id == user.id
    end
  end

  describe "get_credential_by_id/1" do
    test "returns credential with preloaded user" do
      credential_id = :crypto.strong_rand_bytes(32)

      cose_key = %{
        1 => 2,
        3 => -7,
        -1 => 1,
        -2 => :crypto.strong_rand_bytes(32),
        -3 => :crypto.strong_rand_bytes(32)
      }

      {:ok, _user, _credential} = Webauthn.store_credential(credential_id, cose_key, 0)

      assert {:ok, found} = Webauthn.get_credential_by_id(credential_id)
      assert found.credential_id == credential_id
      assert %Nullzara.Users.User{} = found.user
    end

    test "returns error for unknown credential" do
      assert {:error, :not_found} =
               Webauthn.get_credential_by_id(:crypto.strong_rand_bytes(32))
    end
  end

  describe "update_sign_count/2" do
    test "updates the sign count" do
      credential_id = :crypto.strong_rand_bytes(32)

      cose_key = %{
        1 => 2,
        3 => -7,
        -1 => 1,
        -2 => :crypto.strong_rand_bytes(32),
        -3 => :crypto.strong_rand_bytes(32)
      }

      {:ok, _user, credential} = Webauthn.store_credential(credential_id, cose_key, 0)

      assert {:ok, updated} = Webauthn.update_sign_count(credential, 5)
      assert updated.sign_count == 5
    end
  end
end
