defmodule L2E.Zone do
  @moduledoc """
  Zone struct and spatial query functions.

  A zone is a named 3D region defined by a polygon (NPoly) in X/Y with Z bounds.
  The zone type determines gameplay rules for players inside.

  ## Zone types
    - `:peace`   — no PvP, no monster aggro (towns, starting areas)
    - `:pvp`     — forced PvP (arena zones)
    - `:siege`   — castle/clan-hall siege grounds
    - `:no_pvp`  — PvP flag cannot be set here
    - `:damage`  — deals periodic HP damage (lava, acid)
    - `:water`   — swimming context, speed modifier applied
    - `:swamp`   — speed reduction, no mount
    - `:boss`    — instance/boss room, no resurrection by others
    - `:other`   — zone exists but has no combat rule effect (fishing, etc.)

  ## Geometry
  All zones in CT0 Interlude use the NPoly (polygon) shape.
  Point-in-polygon is tested with the ray casting algorithm.
  """

  @enforce_keys [:name, :type, :nodes, :min_z, :max_z]
  defstruct [:name, :type, :nodes, :min_z, :max_z]

  @type zone_type :: :peace | :pvp | :siege | :no_pvp | :damage | :water | :swamp | :boss | :other

  @type t :: %__MODULE__{
          name: String.t(),
          type: zone_type(),
          nodes: [{integer(), integer()}],
          min_z: integer(),
          max_z: integer()
        }

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Returns true if the point `{x, y, z}` is inside this zone.

  Uses ray casting for X/Y polygon containment plus Z-range check.
  """
  @spec contains?(t(), integer(), integer(), integer()) :: boolean()
  def contains?(%__MODULE__{nodes: nodes, min_z: min_z, max_z: max_z}, x, y, z) do
    z >= min_z and z <= max_z and point_in_polygon?(nodes, x, y)
  end

  @doc """
  Maps a Java zone type string to our zone_type atom.
  """
  @spec classify_type(String.t()) :: zone_type()
  def classify_type(type_str) do
    case type_str do
      "PeaceZone" -> :peace
      "TownZone" -> :peace
      "ArenaZone" -> :pvp
      "NoPvPZone" -> :no_pvp
      "SiegeZone" -> :siege
      "CastleZone" -> :siege
      "SiegableHallZone" -> :siege
      "DamageZone" -> :damage
      "SwampZone" -> :swamp
      "WaterZone" -> :water
      "BossZone" -> :boss
      "JailZone" -> :peace
      "OlympiadStadiumZone" -> :pvp
      "ConditionZone" -> :other
      "FishingZone" -> :other
      "NoStoreZone" -> :other
      "ClanHallZone" -> :other
      "RespawnZone" -> :other
      _ -> :other
    end
  end

  # ---------------------------------------------------------------------------
  # Private — ray casting algorithm
  # ---------------------------------------------------------------------------

  # Classic even-odd ray casting: cast a ray along +X from (px, py)
  # and count how many polygon edges it crosses. Odd crossings = inside.
  defp point_in_polygon?(nodes, px, py) do
    ray_cast(nodes, px, py, length(nodes), 0, false)
  end

  defp ray_cast(_nodes, _px, _py, n, i, inside) when i >= n, do: inside

  defp ray_cast(nodes, px, py, n, i, inside) do
    {xi, yi} = Enum.at(nodes, i)
    {xj, yj} = Enum.at(nodes, rem(i + 1, n))

    intersects =
      yi > py != yj > py and
        px < (xj - xi) * (py - yi) / (yj - yi) + xi

    ray_cast(nodes, px, py, n, i + 1, if(intersects, do: not inside, else: inside))
  end
end
