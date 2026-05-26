defmodule L2E.Admin.Commands.Announce do
  @moduledoc """
  Broadcast a server-wide announcement to all online players.

  Usage: admin_announce <message>

  Example: admin_announce Server will restart in 5 minutes!

  The announcement is delivered via Phoenix.PubSub to all player sessions
  subscribed to "world:announcements". It appears as chat_type 9
  (ANNOUNCEMENT) in the client.
  """

  @doc """
  Execute the announce command.
  Args: list of words forming the message.
  """
  @spec execute(list(String.t())) :: {:ok, String.t()} | {:error, String.t()}
  def execute([]) do
    {:error, "admin_announce <message>"}
  end

  def execute(words) when is_list(words) do
    message = Enum.join(words, " ")

    Phoenix.PubSub.broadcast(
      L2E.PubSub,
      "world:announcements",
      {:announcement, message}
    )

    {:ok, "Announced: #{message}"}
  end
end
