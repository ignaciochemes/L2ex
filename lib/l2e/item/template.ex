defmodule L2E.Item.Template do
  @moduledoc """
  Immutable item type definition. Loaded once into ETS at startup.

  ## Fields

    - `type`     — `:weapon | :armor | :etc`
    - `slot`     — paperdoll slot atom; `nil` for `:etc` items
    - `grade`    — `:none | :d | :c | :b | :a | :s`
    - `type1/type2/bodypart` — L2 Interlude packet encoding constants
    - `hp_restore / mp_restore` — consumed when a `:etc` item is used
  """

  @enforce_keys [:item_id, :name, :type]

  defstruct [
    :item_id,
    :name,
    :type,
    :slot,
    :grade,
    p_atk_bonus: 0,
    p_def_bonus: 0,
    m_atk_bonus: 0,
    m_def_bonus: 0,
    stackable: false,
    weight: 0,
    is_tradeable: true,
    sell_price: 0,
    # Packet encoding constants (L2 Interlude protocol)
    type1: 0,
    type2: 0,
    bodypart: 0,
    # Consumable effects (applied on use, `:etc` only)
    hp_restore: 0,
    mp_restore: 0
  ]

  @type slot ::
          :r_hand
          | :l_hand
          | :both_hands
          | :head
          | :chest
          | :legs
          | :feet
          | :gloves
          | :back
          | :neck
          | :l_ear
          | :r_ear
          | :l_finger
          | :r_finger
          | nil

  @type grade :: :none | :d | :c | :b | :a | :s

  @type t :: %__MODULE__{}
end
