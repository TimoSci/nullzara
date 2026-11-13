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

  @doc """
  Derives a CSS linear-gradient string from a wallet address.
  Extracts 3 colors from the address bytes to produce a unique visual identifier.
  """
  def address_gradient(address) do
    bytes =
      address
      |> String.trim_leading("0x")
      |> Base.decode16!(case: :mixed)

    <<r1, g1, b1, r2, g2, b2, r3, g3, b3, _rest::binary>> = bytes
    c1 = "rgb(#{r1},#{g1},#{b1})"
    c2 = "rgb(#{r2},#{g2},#{b2})"
    c3 = "rgb(#{r3},#{g3},#{b3})"
    "linear-gradient(135deg, #{c1}, #{c2}, #{c3})"
  end

  # --- Private: EIP-191 signature recovery ---

  defp recover_address(hex_signature, message) when is_binary(hex_signature) do
    # The signature comes straight from the browser, so it may be anything.
    # It must be 65 bytes of hex: r (32), s (32), v (1).
    with {:ok, <<r::binary-size(32), s::binary-size(32), v>>} <-
           hex_signature |> String.trim_leading("0x") |> Base.decode16(case: :mixed),
         # Ethereum uses 27/28 for v, ex_secp256k1 expects 0/1
         recovery_id = if(v >= 27, do: v - 27, else: v),
         true <- recovery_id in [0, 1],
         # EIP-191 prefixed hash
         hash =
           ExKeccak.hash_256("\x19Ethereum Signed Message:\n#{byte_size(message)}" <> message),
         # public_key is 65 bytes: 0x04 prefix + 64 bytes of key data
         {:ok, <<4, key_data::binary-size(64)>>} <- ExSecp256k1.recover(hash, r, s, recovery_id) do
      <<_::binary-size(12), address_bytes::binary-size(20)>> = ExKeccak.hash_256(key_data)
      {:ok, "0x" <> Base.encode16(address_bytes, case: :lower)}
    else
      _ -> {:error, :invalid_signature}
    end
  end

  defp recover_address(_signature, _message), do: {:error, :invalid_signature}
end
