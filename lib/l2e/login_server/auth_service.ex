defmodule L2E.LoginServer.AuthService do
  @moduledoc """
  Pure module (no process) for account authentication and creation.

  In development mode (`Mix.env() == :dev`), if an account does not exist it
  is created automatically with the supplied password. This lets you connect
  with any client without a prior registration step.

  In production, only existing accounts with matching passwords are accepted.
  """

  import Ecto.Query, only: [from: 2]
  alias L2E.{Repo, DB.Account}

  @doc """
  Authenticate `username`/`password`.

  Returns `{:ok, account}` on success, `{:error, :invalid_credentials}` on
  wrong password, or `{:error, :not_found}` if the account doesn't exist (and
  auto-create is disabled).
  """
  @spec authenticate(String.t(), String.t()) ::
          {:ok, %Account{}} | {:error, :invalid_credentials | :not_found}
  def authenticate(username, password) when is_binary(username) and is_binary(password) do
    case Repo.one(from(a in Account, where: a.username == ^username)) do
      nil ->
        if dev_mode?() do
          auto_create(username, password)
        else
          {:error, :not_found}
        end

      %Account{password_hash: hash} = account ->
        if Pbkdf2.verify_pass(password, hash) do
          {:ok, account}
        else
          # Constant-time dummy check to prevent timing attacks
          Pbkdf2.no_user_verify()
          {:error, :invalid_credentials}
        end
    end
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp auto_create(username, password) do
    changeset = Account.registration_changeset(%{username: username, password: password})

    case Repo.insert(changeset) do
      {:ok, account} ->
        require Logger
        Logger.info("[AuthService] Auto-created account for #{username} (dev mode)")
        {:ok, account}

      {:error, %Ecto.Changeset{errors: errors}} ->
        require Logger
        Logger.warning("[AuthService] Auto-create failed for #{username}: #{inspect(errors)}")
        {:error, :invalid_credentials}
    end
  end

  defp dev_mode?, do: Application.get_env(:l2e, :dev_auto_create_accounts, false)
end
