defmodule L2E.Inventory do
  @moduledoc """
  Per-player inventory process.

  Started when a player enters the world, stopped on logout.
  Registered in `L2E.Session.Registry` under `{:inventory, char_id}`.

  ## Responsibilities

  - Persists items to the `items` DB table on every write.
  - Tracks paperdoll (which item occupies each equipment slot).
  - Computes equipment bonuses (`p_atk`, `p_def`, `m_atk`, `m_def`) used
    by `L2E.Game.Stats.apply_equipment/2`.

  ## Return convention for write operations

  All write calls return `{:ok, change_type, {instance, template}}` on success:

    - `:added`    — new item inserted into inventory
    - `:modified` — existing item changed (count incremented, equip toggled)
    - `:removed`  — item fully consumed / deleted

  The caller maps change_type to the L2 protocol integer:
  1 = added, 2 = modified, 3 = removed.
  """

  use GenServer, restart: :temporary
  require Logger

  import Ecto.Query, only: [from: 2]

  alias L2E.{Repo, DB.Item}
  alias L2E.Item.{Template, TemplateTable, Instance}
  alias L2E.Data.ArmorSetData

  @registry L2E.Session.Registry

  # -----------------------------------------------------------------------
  # Public API
  # -----------------------------------------------------------------------

  def start_link(char_id: char_id) do
    GenServer.start_link(__MODULE__, char_id, name: via_tuple(char_id))
  end

  @spec via_tuple(pos_integer()) :: {:via, Registry, {atom(), {:inventory, pos_integer()}}}
  def via_tuple(char_id) do
    {:via, Registry, {@registry, {:inventory, char_id}}}
  end

  @doc "Returns all items as `{Instance.t(), Template.t()}` pairs."
  @spec get_items(pos_integer()) :: [{Instance.t(), Template.t()}]
  def get_items(char_id) do
    GenServer.call(via_tuple(char_id), :get_items)
  end

  @doc "Adds `count` of `item_id` to inventory."
  @spec add_item(pos_integer(), pos_integer(), pos_integer()) ::
          {:ok, :added | :modified, {Instance.t(), Template.t()}} | {:error, term()}
  def add_item(char_id, item_id, count) do
    GenServer.call(via_tuple(char_id), {:add_item, item_id, count})
  end

  @doc "Uses (equip/consume) the item identified by `item_instance_id`."
  @spec use_item(pos_integer(), pos_integer()) ::
          {:ok, :modified | :removed, {Instance.t(), Template.t()}} | {:error, term()}
  def use_item(char_id, item_instance_id) do
    GenServer.call(via_tuple(char_id), {:use_item, item_instance_id})
  end

  @doc "Returns equipment bonus map for stat computation."
  @spec get_equip_bonuses(pos_integer()) :: map()
  def get_equip_bonuses(char_id) do
    GenServer.call(via_tuple(char_id), :get_equip_bonuses)
  end

  @doc "Removes `amount` of adena (item_id 57) from inventory. Returns :ok or {:error, reason}."
  @spec spend_adena(pos_integer(), pos_integer()) :: :ok | {:error, term()}
  def spend_adena(char_id, amount) when amount > 0 do
    GenServer.call(via_tuple(char_id), {:spend_adena, amount})
  end

  def spend_adena(_char_id, 0), do: :ok

  @doc "Returns the amount of adena (item_id 57) in the inventory."
  @spec get_adena_count(pos_integer()) :: non_neg_integer()
  def get_adena_count(char_id) do
    GenServer.call(via_tuple(char_id), :get_adena_count)
  end

  @doc "Removes `count` of the item instance `item_instance_id` from inventory."
  @spec remove_item(pos_integer(), pos_integer(), pos_integer()) ::
          {:ok, :modified | :removed, {Instance.t(), Template.t()}} | {:error, term()}
  def remove_item(char_id, item_instance_id, count) do
    GenServer.call(via_tuple(char_id), {:remove_item, item_instance_id, count})
  end

  @doc "Returns the total count of items with the given `item_id` (template) in inventory."
  @spec count_item(pos_integer(), pos_integer()) :: non_neg_integer()
  def count_item(char_id, item_id) do
    GenServer.call(via_tuple(char_id), {:count_item, item_id})
  end

  @doc "Removes `count` of item matching `item_id` (template) from inventory."
  @spec remove_item_by_template(pos_integer(), pos_integer(), pos_integer()) ::
          {:ok, :modified | :removed, {Instance.t(), Template.t()}} | {:error, term()}
  def remove_item_by_template(char_id, item_id, count) do
    GenServer.call(via_tuple(char_id), {:remove_item_by_template, item_id, count})
  end

  @doc "Updates the enchant level of the given item instance (by object_id)."
  @spec update_enchant(pos_integer(), pos_integer(), non_neg_integer()) :: :ok
  def update_enchant(char_id, object_id, enchant_level) do
    GenServer.call(via_tuple(char_id), {:update_enchant, object_id, enchant_level})
  end

  # -----------------------------------------------------------------------
  # GenServer callbacks
  # -----------------------------------------------------------------------

  @impl true
  def init(char_id) do
    db_items = Repo.all(from(i in Item, where: i.char_id == ^char_id))
    items = Map.new(db_items, fn i -> {i.id, to_instance(i)} end)
    paperdoll = build_paperdoll(items)
    equip_bonuses = compute_equip_bonuses(items, paperdoll)
    Logger.debug("[Inventory] char_id=#{char_id} loaded #{map_size(items)} items")
    {:ok, %{char_id: char_id, items: items, paperdoll: paperdoll, equip_bonuses: equip_bonuses}}
  end

  @impl true
  def handle_call(:get_items, _from, state) do
    pairs =
      Enum.map(state.items, fn {_id, instance} ->
        {instance, TemplateTable.get(instance.item_id)}
      end)

    {:reply, pairs, state}
  end

  def handle_call({:add_item, item_id, count}, _from, state) do
    case TemplateTable.get(item_id) do
      nil ->
        {:reply, {:error, :unknown_item}, state}

      template ->
        {new_items, instance, change_type} =
          do_add_item(state.items, state.char_id, template, count)

        new_state = %{state | items: new_items}
        {:reply, {:ok, change_type, {instance, template}}, new_state}
    end
  end

  def handle_call({:use_item, item_instance_id}, _from, state) do
    case Map.get(state.items, item_instance_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      instance ->
        template = TemplateTable.get(instance.item_id)

        case handle_use(state, instance, template) do
          {:ok, change_type, updated_instance, new_state} ->
            {:reply, {:ok, change_type, {updated_instance, template}}, new_state}

          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end
    end
  end

  def handle_call(:get_equip_bonuses, _from, state) do
    {:reply, state.equip_bonuses, state}
  end

  def handle_call(:get_adena_count, _from, state) do
    adena_id = 57

    count =
      Enum.find_value(state.items, 0, fn {_, inst} ->
        if inst.item_id == adena_id, do: inst.count || 0, else: nil
      end)

    {:reply, count, state}
  end

  def handle_call({:spend_adena, amount}, _from, state) do
    adena_id = 57

    case Enum.find(state.items, fn {_, inst} -> inst.item_id == adena_id end) do
      nil ->
        {:reply, {:error, :not_found}, state}

      {inst_id, inst} ->
        current = inst.count || 0

        if current < amount do
          {:reply, {:error, :insufficient_adena}, state}
        else
          new_count = current - amount
          updated_inst = %{inst | count: new_count}
          new_items = Map.put(state.items, inst_id, updated_inst)
          db_item = Repo.get!(Item, inst_id)
          Repo.update!(Ecto.Changeset.change(db_item, count: new_count))
          {:reply, :ok, %{state | items: new_items}}
        end
    end
  end

  def handle_call({:remove_item, item_instance_id, count}, _from, state) do
    case Map.get(state.items, item_instance_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      instance ->
        template = TemplateTable.get(instance.item_id)

        cond do
          is_nil(template) ->
            {:reply, {:error, :no_template}, state}

          # Stackable: reduce count or delete if depleted
          template.stackable ->
            new_count = (instance.count || 1) - count

            if new_count <= 0 do
              Repo.delete_all(from(i in Item, where: i.id == ^item_instance_id))
              new_items = Map.delete(state.items, item_instance_id)

              {:reply, {:ok, :removed, {%{instance | count: 0}, template}},
               %{state | items: new_items}}
            else
              Repo.update_all(from(i in Item, where: i.id == ^item_instance_id),
                set: [count: new_count]
              )

              updated = %{instance | count: new_count}
              new_items = Map.put(state.items, item_instance_id, updated)
              {:reply, {:ok, :modified, {updated, template}}, %{state | items: new_items}}
            end

          # Non-stackable: remove single instance
          true ->
            Repo.delete_all(from(i in Item, where: i.id == ^item_instance_id))
            new_items = Map.delete(state.items, item_instance_id)
            {:reply, {:ok, :removed, {instance, template}}, %{state | items: new_items}}
        end
    end
  end

  def handle_call({:count_item, item_id}, _from, state) do
    count =
      Enum.reduce(state.items, 0, fn {_, inst}, acc ->
        if inst.item_id == item_id, do: acc + (inst.count || 1), else: acc
      end)

    {:reply, count, state}
  end

  def handle_call({:remove_item_by_template, item_id, count}, _from, state) do
    case Enum.find(state.items, fn {_, inst} -> inst.item_id == item_id end) do
      nil ->
        {:reply, {:error, :not_found}, state}

      {inst_id, instance} ->
        template = TemplateTable.get(item_id)

        cond do
          is_nil(template) ->
            {:reply, {:error, :no_template}, state}

          template.stackable ->
            new_count = (instance.count || 1) - count

            if new_count <= 0 do
              Repo.delete_all(from(i in Item, where: i.id == ^inst_id))
              new_items = Map.delete(state.items, inst_id)

              {:reply, {:ok, :removed, {%{instance | count: 0}, template}},
               %{state | items: new_items}}
            else
              Repo.update_all(from(i in Item, where: i.id == ^inst_id), set: [count: new_count])
              updated = %{instance | count: new_count}
              new_items = Map.put(state.items, inst_id, updated)
              {:reply, {:ok, :modified, {updated, template}}, %{state | items: new_items}}
            end

          true ->
            Repo.delete_all(from(i in Item, where: i.id == ^inst_id))
            new_items = Map.delete(state.items, inst_id)
            {:reply, {:ok, :removed, {instance, template}}, %{state | items: new_items}}
        end
    end
  end

  def handle_call({:update_enchant, object_id, enchant_level}, _from, state) do
    case Map.get(state.items, object_id) do
      nil ->
        {:reply, :ok, state}

      instance ->
        Repo.update_all(from(i in Item, where: i.id == ^object_id),
          set: [enchant_level: enchant_level]
        )

        updated = %{instance | enchant_level: enchant_level}
        new_items = Map.put(state.items, object_id, updated)
        {:reply, :ok, %{state | items: new_items}}
    end
  end

  # -----------------------------------------------------------------------
  # Private — item operations
  # -----------------------------------------------------------------------

  # Stackable item: merge into existing stack if present
  defp do_add_item(items, char_id, %Template{stackable: true, item_id: item_id} = _tmpl, count) do
    existing =
      Enum.find_value(items, fn {_id, inst} ->
        if inst.item_id == item_id, do: inst, else: nil
      end)

    if existing do
      new_count = existing.count + count
      Repo.update_all(from(i in Item, where: i.id == ^existing.id), set: [count: new_count])
      updated = %{existing | count: new_count}
      {Map.put(items, existing.id, updated), updated, :modified}
    else
      {new_items, inst} = insert_item(items, char_id, item_id, count)
      {new_items, inst, :added}
    end
  end

  defp do_add_item(items, char_id, %Template{item_id: item_id}, count) do
    {new_items, inst} = insert_item(items, char_id, item_id, count)
    {new_items, inst, :added}
  end

  defp insert_item(items, char_id, item_id, count) do
    {:ok, db_item} =
      Repo.insert(%Item{
        char_id: char_id,
        item_id: item_id,
        count: count,
        enchant_level: 0,
        is_equipped: false,
        slot: nil
      })

    instance = to_instance(db_item)
    {Map.put(items, instance.id, instance), instance}
  end

  # -----------------------------------------------------------------------
  # Private — use / equip
  # -----------------------------------------------------------------------

  # Consumable with HP or MP restore
  defp handle_use(state, instance, %Template{type: :etc} = template) do
    if template.hp_restore > 0 or template.mp_restore > 0 do
      {new_items, consumed, change_type} = consume_item(state.items, instance)
      {:ok, change_type, consumed, %{state | items: new_items}}
    else
      {:error, :cannot_use}
    end
  end

  # Equipment: toggle equip/unequip
  defp handle_use(state, instance, %Template{type: type, slot: slot} = _tmpl)
       when type in [:weapon, :armor] and not is_nil(slot) do
    if instance.is_equipped do
      unequip(state, instance, slot)
    else
      equip(state, instance, slot)
    end
  end

  defp handle_use(_state, _instance, _template), do: {:error, :cannot_use}

  defp unequip(state, instance, slot) do
    updated = %{instance | is_equipped: false, slot: nil}
    persist_equip(updated)
    new_items = Map.put(state.items, instance.id, updated)
    new_paperdoll = Map.delete(state.paperdoll, slot)
    new_bonuses = compute_equip_bonuses(new_items, new_paperdoll)

    new_state = %{state | items: new_items, paperdoll: new_paperdoll, equip_bonuses: new_bonuses}

    {:ok, :modified, updated, new_state}
  end

  defp equip(state, instance, slot) do
    # If something else is already in this slot, unequip it first
    {items_after, paperdoll_after} =
      case Map.get(state.paperdoll, slot) do
        nil ->
          {state.items, state.paperdoll}

        old_id ->
          old_inst = Map.fetch!(state.items, old_id)
          old_unequipped = %{old_inst | is_equipped: false, slot: nil}
          persist_equip(old_unequipped)

          {
            Map.put(state.items, old_id, old_unequipped),
            Map.delete(state.paperdoll, slot)
          }
      end

    updated = %{instance | is_equipped: true, slot: slot}
    persist_equip(updated)
    new_items = Map.put(items_after, instance.id, updated)
    new_paperdoll = Map.put(paperdoll_after, slot, instance.id)
    new_bonuses = compute_equip_bonuses(new_items, new_paperdoll)

    new_state = %{state | items: new_items, paperdoll: new_paperdoll, equip_bonuses: new_bonuses}

    {:ok, :modified, updated, new_state}
  end

  defp consume_item(items, instance) do
    if instance.count > 1 do
      new_count = instance.count - 1
      Repo.update_all(from(i in Item, where: i.id == ^instance.id), set: [count: new_count])
      updated = %{instance | count: new_count}
      {Map.put(items, instance.id, updated), updated, :modified}
    else
      Repo.delete_all(from(i in Item, where: i.id == ^instance.id))
      {Map.delete(items, instance.id), instance, :removed}
    end
  end

  defp persist_equip(instance) do
    slot_str = if instance.slot, do: Atom.to_string(instance.slot), else: nil

    Repo.update_all(
      from(i in Item, where: i.id == ^instance.id),
      set: [is_equipped: instance.is_equipped, slot: slot_str]
    )
  end

  # -----------------------------------------------------------------------
  # Private — helpers
  # -----------------------------------------------------------------------

  defp build_paperdoll(items) do
    Enum.reduce(items, %{}, fn {id, instance}, acc ->
      if instance.is_equipped and not is_nil(instance.slot) do
        Map.put(acc, instance.slot, id)
      else
        acc
      end
    end)
  end

  # Paperdoll integer slot IDs as used by ArmorSetData (chest=10, legs=7, head=6, gloves=8, feet=9)
  @paperdoll_ids %{head: 6, legs: 7, gloves: 8, feet: 9, chest: 10}

  defp slot_to_paperdoll_id(slot), do: Map.get(@paperdoll_ids, slot)

  defp compute_equip_bonuses(items, paperdoll) do
    base_bonuses =
      Enum.reduce(paperdoll, %{p_atk: 0, p_def: 0, m_atk: 0, m_def: 0}, fn {_slot, id}, acc ->
        with %Instance{} = inst <- Map.get(items, id),
             %Template{} = tmpl <- TemplateTable.get(inst.item_id) do
          %{
            acc
            | p_atk: acc.p_atk + tmpl.p_atk_bonus,
              p_def: acc.p_def + tmpl.p_def_bonus,
              m_atk: acc.m_atk + tmpl.m_atk_bonus,
              m_def: acc.m_def + tmpl.m_def_bonus
          }
        else
          _ -> acc
        end
      end)

    slot_to_template_id =
      for {slot, inst_id} <- paperdoll,
          inst = Map.get(items, inst_id),
          not is_nil(inst),
          tmpl = TemplateTable.get(inst.item_id),
          not is_nil(tmpl),
          slot_int = slot_to_paperdoll_id(slot),
          not is_nil(slot_int),
          into: %{} do
        {slot_int, tmpl.item_id}
      end

    set_bonus = ArmorSetData.check_set_bonus(slot_to_template_id)
    Map.merge(base_bonuses, set_bonus, fn _k, v1, v2 -> v1 + v2 end)
  end

  defp to_instance(%Item{} = i) do
    %Instance{
      id: i.id,
      item_id: i.item_id,
      count: i.count,
      enchant_level: i.enchant_level,
      is_equipped: i.is_equipped,
      slot: parse_slot(i.slot),
      soul_type: i.soul_type || 0,
      soul_level: i.soul_level || 0
    }
  end

  defp parse_slot(nil), do: nil

  defp parse_slot(str) do
    try do
      String.to_existing_atom(str)
    rescue
      ArgumentError -> nil
    end
  end
end
