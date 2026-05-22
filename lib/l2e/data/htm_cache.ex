defmodule L2E.Data.HtmCache do
  @moduledoc """
  Lazy-loading, in-memory cache for NPC dialog HTML files.

  HTML files are stored under `priv/game/data/html/<path>` and are
  loaded on first access.  Subsequent calls return the cached content
  with no file I/O.

  Variable substitution
  ---------------------
  `get/2` accepts an optional `vars` map.  Each key-value pair in `vars`
  replaces every occurrence of `%KEY%` in the template, e.g.:

      HtmCache.get("default/merchant.htm", %{"name" => "Ignacio"})

  Falls back to `nil` when the file does not exist.
  """

  use Agent
  require Logger

  @base_subpath Path.join(["game", "data", "html"])

  def start_link(_opts) do
    Agent.start_link(fn -> %{} end, name: __MODULE__)
  end

  @doc """
  Return the HTML for `path`, loading from disk on first access.
  Pass `vars` to replace `%KEY%` tokens in the template.
  """
  @spec get(String.t(), map()) :: String.t() | nil
  def get(path, vars \\ %{}) do
    raw = fetch_raw(path)
    if raw && map_size(vars) > 0, do: substitute(raw, vars), else: raw
  end

  # -----------------------------------------------------------------------
  # Private helpers
  # -----------------------------------------------------------------------

  defp fetch_raw(path) do
    Agent.get_and_update(__MODULE__, fn cache ->
      case Map.fetch(cache, path) do
        {:ok, content} ->
          {content, cache}

        :error ->
          abs = html_path(path)

          case File.read(abs) do
            {:ok, content} ->
              Logger.debug("[HtmCache] Loaded #{path}")
              {content, Map.put(cache, path, content)}

            {:error, reason} ->
              Logger.debug("[HtmCache] File not found: #{path} (#{inspect(reason)})")
              {nil, cache}
          end
      end
    end)
  end

  defp html_path(path) do
    priv = :code.priv_dir(:l2e) |> List.to_string()
    Path.join([priv, @base_subpath, path])
  end

  defp substitute(html, vars) do
    Enum.reduce(vars, html, fn {key, value}, acc ->
      String.replace(acc, "%#{key}%", to_string(value))
    end)
  end
end
