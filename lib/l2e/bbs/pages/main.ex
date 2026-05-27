defmodule L2E.BBS.Pages.Main do
  @moduledoc """
  Community Board main page.

  Returns a static HTML string in standard L2 BBS format.
  """

  def render(_player_state) do
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
    <font color=LEVEL>L2E Community Board</font>
    </td></tr></table>
    <br>
    <table border=0 width=610>
    <tr><td width=200><font color=LEVEL>Server Info</font></td></tr>
    <tr><td>Server: L2E - Interlude</td></tr>
    <tr><td>Built with Elixir/OTP</td></tr>
    </table>
    </center>
    </body></html>
    """
  end
end
