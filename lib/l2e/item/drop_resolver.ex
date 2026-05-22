defmodule L2E.Item.DropResolver do
  @moduledoc """
  Delegates drop resolution to L2E.Data.DropTable (loaded from NPC XML files).
  Falls back to a minimal adena drop if the NPC has no XML entry.
  """

  alias L2E.NPC.Template

  @spec resolve(Template.t()) :: [{pos_integer(), pos_integer()}]
  def resolve(%Template{npc_id: npc_id}) do
    L2E.Data.DropTable.resolve(npc_id)
  rescue
    _ -> [{57, 1 + :rand.uniform(5)}]
  end
end
