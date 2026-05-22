defmodule L2E.Siege.Castle do
  @moduledoc """
  Castle data struct.

  Represents a siegeable castle in the world.
  Reference: Castle.java (behavioral reference only)
  """

  defstruct [
    :id,
    :name,
    :owner_clan_id,
    :siege_date,
    # :idle | :preparation | :in_progress | :ended
    :siege_status,
    :tax_rate,
    :treasury
  ]

  @type t :: %__MODULE__{
          id: non_neg_integer(),
          name: String.t(),
          owner_clan_id: pos_integer() | nil,
          siege_date: DateTime.t() | nil,
          siege_status: :idle | :preparation | :in_progress | :ended,
          tax_rate: non_neg_integer(),
          treasury: non_neg_integer()
        }

  # Interlude castle IDs and names
  @castles [
    %{id: 1, name: "Gludio"},
    %{id: 2, name: "Dion"},
    %{id: 3, name: "Giran"},
    %{id: 4, name: "Oren"},
    %{id: 5, name: "Aden"},
    %{id: 6, name: "Innadril"},
    %{id: 7, name: "Goddard"},
    %{id: 8, name: "Rune"},
    %{id: 9, name: "Schuttgart"}
  ]

  def all_castles, do: @castles

  def new(id, name) do
    %__MODULE__{
      id: id,
      name: name,
      owner_clan_id: nil,
      siege_date: nil,
      siege_status: :idle,
      tax_rate: 15,
      treasury: 0
    }
  end
end
