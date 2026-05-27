defmodule L2E.Item.Instance do
  @moduledoc """
  A concrete item owned by a player.

  The `id` field is the DB primary key and is also used as the L2 object_id
  sent to the client (every in-game object needs a globally unique integer ID).
  """

  @enforce_keys [:id, :item_id]

  defstruct [
    :id,
    :item_id,
    count: 1,
    enchant_level: 0,
    is_equipped: false,
    slot: nil,
    soul_type: 0,
    soul_level: 0
  ]

  @type t :: %__MODULE__{}
end
