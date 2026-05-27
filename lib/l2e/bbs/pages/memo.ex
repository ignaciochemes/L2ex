defmodule L2E.BBS.Pages.Memo do
  @moduledoc """
  Community Board memo page — stub implementation.

  Full memo functionality (personal notes stored in DB) is deferred.
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
    <font color=LEVEL>Memo</font>
    </td></tr></table>
    <br>
    <table border=0 width=610>
    <tr><td>Memo feature is under construction.</td></tr>
    </table>
    </center>
    </body></html>
    """
  end
end
