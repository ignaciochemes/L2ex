defmodule L2E.Data.ExperienceTable do
  @moduledoc """
  Cumulative XP required to reach each level in L2 Interlude.

  Source: L2J Mobius Interlude experience.xml (exact values).
  Level 1 = 0 XP (you start at level 1).
  Level 2 = 68 XP total, etc.

  Used by `L2E.Game.Stats.xp_to_next_level/1` to compute the XP delta
  between consecutive levels.
  """

  # {level, cumulative_xp_to_reach_this_level}
  @table [
    {1, 0},
    {2, 68},
    {3, 363},
    {4, 1_168},
    {5, 2_884},
    {6, 6_038},
    {7, 11_201},
    {8, 19_028},
    {9, 30_291},
    {10, 45_927},
    {11, 67_032},
    {12, 95_008},
    {13, 130_625},
    {14, 175_982},
    {15, 233_481},
    {16, 305_902},
    {17, 396_419},
    {18, 508_633},
    {19, 646_616},
    {20, 814_921},
    {21, 1_019_567},
    {22, 1_266_101},
    {23, 1_560_648},
    {24, 1_909_984},
    {25, 2_321_582},
    {26, 2_803_688},
    {27, 3_365_389},
    {28, 4_016_695},
    {29, 4_768_647},
    {30, 5_633_410},
    {31, 6_624_460},
    {32, 7_756_771},
    {33, 9_046_030},
    {34, 10_509_800},
    {35, 12_166_698},
    {36, 14_037_567},
    {37, 16_144_693},
    {38, 18_512_100},
    {39, 21_165_701},
    {40, 24_133_538},
    {41, 27_446_041},
    {42, 31_135_318},
    {43, 35_236_326},
    {44, 39_786_127},
    {45, 44_824_155},
    {46, 50_392_465},
    {47, 56_535_973},
    {48, 63_302_651},
    {49, 70_743_674},
    {50, 78_913_625},
    {51, 87_870_765},
    {52, 97_677_323},
    {53, 108_397_730},
    {54, 120_098_981},
    {55, 132_849_945},
    {56, 146_721_832},
    {57, 161_788_480},
    {58, 178_126_677},
    {59, 195_815_568},
    {60, 214_936_030},
    {61, 248_855_050},
    {62, 289_076_808},
    {63, 336_519_543},
    {64, 392_385_555},
    {65, 458_126_578},
    {66, 535_415_735},
    {67, 625_200_462},
    {68, 729_777_350},
    {69, 850_851_600},
    {70, 990_621_300},
    {71, 1_151_869_300},
    {72, 1_337_014_200},
    {73, 1_549_166_400},
    {74, 1_792_277_800},
    {75, 2_070_299_700},
    {76, 2_388_339_100},
    {77, 2_751_846_900},
    {78, 3_166_856_900},
    {79, 3_641_200_000},
    {80, 4_183_706_000},
    {81, 4_804_405_500},
    {82, 5_514_748_600},
    {83, 6_327_769_600},
    {84, 7_258_340_600},
    {85, 8_323_387_200}
  ]

  # Build a map at compile time for O(1) lookups
  @xp_map Map.new(@table)

  @doc """
  Returns the cumulative XP required to reach `level`.
  Returns 0 for level 1 (or below). Returns the level-85 value for anything above 85.
  """
  @spec get_xp_for_level(pos_integer()) :: non_neg_integer()
  def get_xp_for_level(level) when level <= 1, do: 0
  def get_xp_for_level(level) when level > 85, do: Map.fetch!(@xp_map, 85)
  def get_xp_for_level(level), do: Map.fetch!(@xp_map, level)

  @doc "Maximum supported player level."
  @spec max_level() :: pos_integer()
  def max_level, do: 85
end
