defmodule Nullzara.Wallet do
  @moduledoc """
  Context for Ethereum wallet authentication via EIP-191 personal_sign.
  """

  alias Nullzara.Repo
  alias Nullzara.Users.User
  alias Nullzara.Wallet.Credential

  import Ecto.Query

  @sign_message_prefix "Sign in to Nullzara\n\nNonce: "

  def generate_nonce do
    :crypto.strong_rand_bytes(32) |> Base.encode16(case: :lower)
  end

  def build_sign_message(nonce) do
    @sign_message_prefix <> nonce
  end

  def verify_signature(hex_signature, message, claimed_address) do
    with {:ok, address} <- recover_address(hex_signature, message) do
      if String.downcase(address) == String.downcase(claimed_address) do
        {:ok, address}
      else
        {:error, :address_mismatch}
      end
    end
  end

  def store_credential(address) do
    Repo.transaction(fn ->
      {:ok, user} =
        %User{}
        |> User.registration_changeset(%{name: "Anonymous"})
        |> Repo.insert()

      {:ok, credential} =
        %Credential{}
        |> Credential.changeset(%{address: address})
        |> Ecto.Changeset.put_change(:user_id, user.id)
        |> Repo.insert()

      {user, credential}
    end)
    |> case do
      {:ok, {user, credential}} -> {:ok, user, credential}
      {:error, reason} -> {:error, reason}
    end
  end

  def get_credential_by_address(address) do
    query =
      from c in Credential,
        where: c.address == ^String.downcase(address),
        preload: [:user]

    case Repo.one(query) do
      nil -> {:error, :not_found}
      credential -> {:ok, credential}
    end
  end

  def attach_credential(user, address) do
    %Credential{}
    |> Credential.changeset(%{address: address})
    |> Ecto.Changeset.put_change(:user_id, user.id)
    |> Repo.insert()
  end

  def detach_credential(credential) do
    Repo.delete(credential)
  end

  # --- Private: EIP-191 signature recovery ---

  defp recover_address(hex_signature, message) do
    # Strip 0x prefix and decode
    raw_sig = hex_signature |> String.trim_leading("0x") |> Base.decode16!(case: :mixed)

    # Split into r (32), s (32), v (1)
    <<r::binary-size(32), s::binary-size(32), v>> = raw_sig

    # Normalize v: Ethereum uses 27/28, ex_secp256k1 expects 0/1
    recovery_id = if v >= 27, do: v - 27, else: v

    # EIP-191 prefixed hash
    prefixed = "\x19Ethereum Signed Message:\n#{byte_size(message)}" <> message
    hash = ExKeccak.hash_256(prefixed)

    # Recover public key
    case ExSecp256k1.recover(hash, r, s, recovery_id) do
      {:ok, public_key} ->
        # public_key is 65 bytes: 0x04 prefix + 64 bytes of key data
        <<4, key_data::binary-size(64)>> = public_key
        <<_::binary-size(12), address_bytes::binary-size(20)>> = ExKeccak.hash_256(key_data)
        {:ok, "0x" <> Base.encode16(address_bytes, case: :lower)}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
