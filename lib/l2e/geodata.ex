defmodule L2E.Geodata do
  @moduledoc """
  M20: Geodata — line-of-sight and pathfinding stubs.

  This module provides a clean interface for geodata checks. The stubs always
  return permissive results (no geodata loaded), which means collisions and
  LoS checks are disabled. Replace stub implementations with a real GeoEngine
  once a `.l2j` or binary geodata format is parsed.

  ## Real implementation notes (future)
  - Load region geodata files (e.g. `geodata/20_21.l2j`) into ETS
  - `can_see?/2`: ray-cast between two 3D points checking height blocks
  - `can_move?/3`: check each step along a path for floor/wall collisions
  """

  @type pos :: {integer(), integer(), integer()}

  @doc "Returns true if there is line-of-sight between two positions."
  @spec can_see?(pos(), pos()) :: boolean()
  def can_see?(_from, _to), do: true

  @doc "Returns true if movement from `from` to `to` is unobstructed."
  @spec can_move?(pos(), pos(), non_neg_integer()) :: boolean()
  def can_move?(_from, _to, _heading), do: true

  @doc "Returns the valid ground Z coordinate at (x, y). Stub returns the given z unchanged."
  @spec get_height(integer(), integer(), integer()) :: integer()
  def get_height(_x, _y, z), do: z
end
