defmodule L2E.BBS.Pages.Clan do
  @moduledoc """
  Community Board clan info page.

  Shows the player's own clan information. If the player is not in a clan,
  displays a "not in a clan" message.
  """

  def render(player_state) do
    clan_html =
      if Map.get(player_state, :clan_id) && player_state.clan_id != 0 do
        "<tr><td>Clan ID: #{player_state.clan_id}</td></tr>"
      else
        "<tr><td>You are not in a clan.</td></tr>"
      end

    """
    <html><body>
    <br><br>
    <center>
    <table border=0 width=610><tr><td>
    <a action="bypass _bbsmain">Community</a>&nbsp;|&nbsp;
    <a action="bypass _bbsclan">My Clan</a>&nbsp;|&nbsp;
    <a action="bypass _bbsmemo">Memo</a>
    </td></tr></table>
    <br>
    <table border=0 width=610 bgcolor=666666><tr><td>
    <font color=LEVEL>My Clan</font>
    </td></tr></table>
    <br>
    <table border=0 width=610>
    #{clan_html}
    </table>
    </center>
    </body></html>
    """
  end
end
