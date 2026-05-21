defmodule L2E.DB.Account do
  use Ecto.Schema
  import Ecto.Changeset

  @moduledoc """
  Persistent account record. Only auth fields live here — all game logic
  stays in PlayerSession and pure modules.
  """

  schema "accounts" do
    field(:username, :string)
    field(:password_hash, :string)
    timestamps(type: :utc_datetime)
  end

  @spec registration_changeset(map()) :: Ecto.Changeset.t()
  def registration_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:username])
    |> validate_required([:username])
    |> validate_length(:username, min: 1, max: 32)
    |> unique_constraint(:username)
    |> put_password_hash(attrs)
  end

  defp put_password_hash(changeset, %{password: pw}) when is_binary(pw) and pw != "" do
    put_change(changeset, :password_hash, Pbkdf2.hash_pwd_salt(pw))
  end

  defp put_password_hash(changeset, _), do: changeset
end
