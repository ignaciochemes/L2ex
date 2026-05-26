defmodule L2E.DB.OlympiadHistory do
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  schema "olympiad_histories" do
    field(:cycle, :integer)
    field(:winner_char_id, :integer)
    field(:winner_char_name, :string)
    field(:winner_class_id, :integer)
    field(:loser_char_id, :integer)
    field(:loser_char_name, :string)
    field(:loser_class_id, :integer)
    field(:points_delta, :integer)
    field(:match_duration_s, :integer)
    timestamps()
  end

  def changeset(struct, params) do
    struct
    |> cast(params, [:cycle, :winner_char_id, :winner_char_name, :winner_class_id,
                     :loser_char_id, :loser_char_name, :loser_class_id, :points_delta,
                     :match_duration_s])
    |> validate_required([:cycle, :winner_char_id, :winner_char_name, :winner_class_id,
                          :loser_char_id, :loser_char_name, :loser_class_id, :points_delta])
  end

  def insert(cycle, winner, loser, points_delta) do
    %__MODULE__{}
    |> changeset(%{
      cycle: cycle,
      winner_char_id: winner.char_id,
      winner_char_name: winner.char_name,
      winner_class_id: winner.class_id,
      loser_char_id: loser.char_id,
      loser_char_name: loser.char_name,
      loser_class_id: loser.class_id,
      points_delta: points_delta
    })
    |> L2E.Repo.insert()
  end

  def get_by_cycle(cycle) do
    L2E.Repo.all(from(h in __MODULE__, where: h.cycle == ^cycle, order_by: [desc: h.inserted_at]))
  end
end
