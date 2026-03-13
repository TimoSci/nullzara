defmodule Nullzara.Webauthn do
  @moduledoc """
  Context for WebAuthn passkey registration and authentication.
  """

  alias Nullzara.Repo
  alias Nullzara.Users.User
  alias Nullzara.Webauthn.Credential

  import Ecto.Query

  def generate_registration_challenge do
    Wax.new_registration_challenge(
      attestation: "none",
      rp_name: Application.get_env(:wax_, :rp_name, "Nullzara")
    )
  end

  def generate_authentication_challenge do
    Wax.new_authentication_challenge(user_verification: "preferred")
  end

  def verify_registration(attestation_object, client_data_json, challenge) do
    Wax.register(attestation_object, client_data_json, challenge)
  end

  def verify_authentication(
        credential_id,
        authenticator_data,
        signature,
        client_data_json,
        challenge
      ) do
    case get_credential_by_id(credential_id) do
      {:ok, credential} ->
        cose_key = restore_cose_key(credential.public_key)
        credentials = [{credential.credential_id, cose_key}]

        case Wax.authenticate(
               credential_id,
               authenticator_data,
               signature,
               client_data_json,
               challenge,
               credentials
             ) do
          {:ok, auth_data} ->
            {:ok, _} = update_sign_count(credential, auth_data.sign_count)
            {:ok, credential.user}

          {:error, _} = error ->
            error
        end

      {:error, :not_found} ->
        {:error, :credential_not_found}
    end
  end

  def store_credential(credential_id, cose_key, sign_count) do
    Repo.transaction(fn ->
      {:ok, user} =
        %User{}
        |> User.registration_changeset(%{name: "Anonymous"})
        |> Repo.insert()

      serialized_key = serialize_cose_key(cose_key)

      {:ok, credential} =
        %Credential{}
        |> Credential.changeset(%{
          credential_id: credential_id,
          public_key: serialized_key,
          sign_count: sign_count
        })
        |> Ecto.Changeset.put_change(:user_id, user.id)
        |> Repo.insert()

      {user, credential}
    end)
    |> case do
      {:ok, {user, credential}} -> {:ok, user, credential}
      {:error, reason} -> {:error, reason}
    end
  end

  def get_credential_by_id(credential_id) do
    query =
      from c in Credential,
        where: c.credential_id == ^credential_id,
        preload: [:user]

    case Repo.one(query) do
      nil -> {:error, :not_found}
      credential -> {:ok, credential}
    end
  end

  def update_sign_count(credential, new_count) do
    credential
    |> Credential.changeset(%{sign_count: new_count})
    |> Repo.update()
  end

  defp serialize_cose_key(cose_key) do
    Map.new(cose_key, fn {k, v} -> {to_string(k), serialize_value(v)} end)
  end

  defp serialize_value(v) when is_binary(v), do: Base.encode64(v)
  defp serialize_value(v), do: v

  def restore_cose_key(stored_map) do
    Map.new(stored_map, fn {k, v} ->
      {String.to_integer(k), restore_value(v)}
    end)
  end

  defp restore_value(v) when is_binary(v) do
    case Base.decode64(v) do
      {:ok, decoded} -> decoded
      :error -> v
    end
  end

  defp restore_value(v), do: v
end
