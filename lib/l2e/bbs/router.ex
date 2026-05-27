defmodule L2E.BBS.Router do
  @moduledoc """
  Pure dispatcher for Community Board (BBS) bypass commands.

  No GenServer — each request reads live data and returns an HTML string.
  BBS is stateless from the server perspective.
  """

  def handle_bypass(bypass_cmd, player_state) do
    cond do
      bypass_cmd == "_bbshome" or bypass_cmd == "_bbsmain" ->
        L2E.BBS.Pages.Main.render(player_state)

      String.starts_with?(bypass_cmd, "_bbsclan") ->
        L2E.BBS.Pages.Clan.render(player_state)

      String.starts_with?(bypass_cmd, "_bbsmemo") ->
        L2E.BBS.Pages.Memo.render(player_state)

      true ->
        L2E.BBS.Pages.Main.render(player_state)
    end
  end
end
