defmodule L2E.World.RegionCoords do
  @moduledoc """
  Pure functions for world coordinate ↔ region grid math.

  The world is divided into a uniform grid.
  Each cell covers REGION_SIZE × REGION_SIZE game units.

  All functions are side-effect free.
  """

  # Size of each region cell in L2 world units.
  # L2 Interlude maps are roughly 327680 × 327680 units.
  # 256 × 256 cells at 1280 units each gives reasonable granularity.
  @region_size 1280

  @doc "Convert world (x, y) to grid cell {gx, gy}."
  @spec to_grid(integer(), integer()) :: {integer(), integer()}
  def to_grid(x, y) do
    {div(x, @region_size), div(y, @region_size)}
  end

  @doc "PubSub topic for a region cell."
  @spec topic({integer(), integer()}) :: String.t()
  def topic({gx, gy}), do: "region:#{gx}:#{gy}"

  @doc "Returns the 9 grid cells around (and including) the given cell."
  @spec aoi_cells({integer(), integer()}) :: [{integer(), integer()}]
  def aoi_cells({gx, gy}) do
    for dx <- -1..1, dy <- -1..1, do: {gx + dx, gy + dy}
  end

  @doc "Squared distance between two world positions (avoids sqrt for comparisons)."
  @spec sq_distance({integer(), integer(), integer()}, {integer(), integer(), integer()}) ::
          non_neg_integer()
  def sq_distance({x1, y1, z1}, {x2, y2, z2}) do
    (x2 - x1) * (x2 - x1) + (y2 - y1) * (y2 - y1) + (z2 - z1) * (z2 - z1)
  end
end
