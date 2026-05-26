defmodule L2E.NPC.HtmlUtils do
  @moduledoc """
  HTML template utilities for NPC dialogs.

  Provides variable substitution and template rendering functions
  for dynamic NPC dialog generation.
  """

  @doc """
  Substitute variables in an HTML template string.

  Variables are marked with `%varName%` syntax and will be replaced with
  corresponding values from the context map. Unknown variables are left as-is.

  ## Examples

      iex> HtmlUtils.substitute_vars("<p>Hello %charName%</p>", %{"charName" => "Ignacio"})
      "<p>Hello Ignacio</p>"

      iex> HtmlUtils.substitute_vars("<p>%npcId%</p>", %{"npcId" => "1234"})
      "<p>1234</p>"

  ## Common variables
  - `%charName%` — player character name
  - `%npcName%` — NPC name
  - `%npcId%` — NPC template ID
  - `%objectId%` — NPC object instance ID (for bypass commands)
  - `%classId%` — player class ID
  - `%level%` — player level
  - `%fee%` — teleport fee or item cost
  - `%dest_x%`, `%dest_y%`, `%dest_z%` — destination coordinates
  """
  @spec substitute_vars(String.t(), map()) :: String.t()
  def substitute_vars(html, vars) when is_binary(html) and is_map(vars) do
    Enum.reduce(vars, html, fn {key, value}, acc ->
      String.replace(acc, "%#{key}%", to_string(value))
    end)
  end

  def substitute_vars(html, _vars) when is_binary(html), do: html

  @doc """
  Load and render an HTML template with variable substitution.

  This is a convenience wrapper around HtmCache that loads a file and
  substitutes variables in one operation.

  Returns `{:ok, html_string}` or `{:error, :not_found}`.
  """
  @spec load_and_render(String.t(), map()) :: {:ok, String.t()} | {:error, :not_found}
  def load_and_render(path, vars \\ %{}) when is_binary(path) and is_map(vars) do
    case L2E.Data.HtmCache.get(path, vars) do
      nil -> {:error, :not_found}
      html -> {:ok, html}
    end
  end

  @doc """
  Load an HTML template without variable substitution.

  Returns `{:ok, html_string}` or `{:error, :not_found}`.
  """
  @spec load(String.t()) :: {:ok, String.t()} | {:error, :not_found}
  def load(path) when is_binary(path) do
    case L2E.Data.HtmCache.get(path) do
      nil -> {:error, :not_found}
      html -> {:ok, html}
    end
  end
end
