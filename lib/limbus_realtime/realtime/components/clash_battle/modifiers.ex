defmodule LimbusRealtime.Realtime.Components.ClashBattle.Modifiers do
  alias LimbusRealtime.Realtime.Components.ClashBattle.StatusData

  def resolve_skill(item, skill, round, opts \\ %{}) do
    Enum.reduce(Map.get(item, "modifiers", []) |> Enum.reverse(), to_string(skill), fn modifier,
                                                                                       skill ->
      if skill_modifier_active?(modifier["condition"], item, round, opts) do
        apply_skill_effect(modifier["effect"], item, skill)
      else
        skill
      end
    end)
  end

  defp skill_modifier_active?(
         %{"type" => "status", "status" => status, "owner" => "unique", "value" => value},
         item,
         round,
         _opts
       ) do
    status_data = Enum.find(item["statuses"], fn st -> st["id"] == status end)
    Enum.at(status_data["values"], round.unique_statuses_tier) >= value
  end

  defp skill_modifier_active?(
         %{
           "type" => "status",
           "status" => status,
           "owner" => owner,
           "statusType" => status_type,
           "value" => value
         },
         _item,
         round,
         _opts
       ) do
    side = if owner == "self", do: round.self, else: round.target

    field =
      case status_type do
        "Potency" -> :potency
        "Count" -> :count
      end

    (side.statuses[status][field] || 0) >= value
  end

  defp skill_modifier_active?(
         %{"type" => "status-missing", "status" => status, "owner" => owner},
         item,
         round,
         _opts
       ) do
    case owner do
      "unique" ->
        status_data = Enum.find(item["statuses"], fn st -> st["id"] == status end)
        status_data == nil || Enum.at(status_data["values"], round.unique_statuses_tier) == 0

      _ ->
        side = if owner == "self", do: round.self, else: round.target

        not Map.has_key?(side.statuses, status)
    end
  end

  defp skill_modifier_active?(
         %{"type" => "sp", "mode" => mode, "value" => value},
         _item,
         round,
         _opts
       ) do
    case mode do
      "higher" -> round.self.sp > value
      "lower" -> round.self.sp < value
    end
  end

  defp skill_modifier_active?(
         %{"type" => "negative-effects", "value" => value},
         _item,
         round,
         _opts
       ) do
    count =
      StatusData.all()
      |> Enum.count(fn {status, data} ->
        data["type"] == "negative" and Map.has_key?(round.target.statuses, status)
      end)

    count >= value
  end

  defp skill_modifier_active?(%{"type" => "skills-left", "value" => value}, _item, _round, opts) do
    Map.has_key?(opts, :counts) and opts.counts |> Enum.take(3) |> Enum.sum() == value
  end

  defp skill_modifier_active?(_, _, _, _) do
    false
  end

  defp apply_skill_effect(%{"type" => "replace", "slot" => slot, "key" => key}, _item, skill) do
    if to_string(skill) == to_string(slot) do
      key
    else
      skill
    end
  end

  defp apply_skill_effect(_, _, skill) do
    skill
  end

  def apply_round_start(state, round_number) do
    participants =
      Map.new(state.participants, fn {client_id, participant} ->
        {skill_counts, bonus_skill_triggered} =
          Enum.reduce(
            participant.identities,
            {participant.skill_counts, participant.bonus_skill_triggered},
            fn identity_id, {skill_counts, bonus_skill_triggered} ->
              identity = Map.fetch!(state.item_data, identity_id)

              {counts, triggered} =
                Enum.reduce(
                  Map.get(identity, "modifiers", []),
                  {Map.fetch!(skill_counts, identity_id), bonus_skill_triggered},
                  fn modifier, {counts, triggered} ->
                    if not MapSet.member?(triggered, identity_id) and
                         round_modifier_active?(modifier["condition"], round_number, counts) do
                      {
                        apply_round_effect(modifier["effect"], counts),
                        MapSet.put(triggered, identity_id)
                      }
                    else
                      {counts, triggered}
                    end
                  end
                )

              {Map.put(skill_counts, identity_id, counts), triggered}
            end
          )

        {client_id,
         %{participant | skill_counts: skill_counts, bonus_skill_triggered: bonus_skill_triggered}}
      end)

    %{state | participants: participants}
  end

  defp round_modifier_active?(%{"type" => "rounds", "value" => value}, round_number, _) do
    rem(round_number, value) == 0
  end

  defp round_modifier_active?(%{"type" => "rounds-once", "value" => value}, round_number, _) do
    round_number == value
  end

  defp round_modifier_active?(%{"type" => "rounds-increasing", "value" => value}, round_number, _) do
    triangular_multiple?(round_number, value, 1, 2)
  end

  defp round_modifier_active?(%{"type" => "skills-left", "value" => value}, _, skill_counts) do
    Enum.sum(skill_counts) == value
  end

  defp round_modifier_active?(_, _, _) do
    false
  end

  defp apply_round_effect(%{"type" => "add-skill-use", "slot" => slot}, skill_counts) do
    if slot == 4 and Enum.at(skill_counts, 3, 0) == 1 do
      skill_counts
    else
      List.update_at(skill_counts, slot - 1, &(&1 + 1))
    end
  end

  defp apply_round_effect(_, skill_counts) do
    skill_counts
  end

  defp triangular_multiple?(round_number, value, n, increment) do
    multiple = value * n

    cond do
      multiple == round_number -> true
      multiple > round_number -> false
      true -> triangular_multiple?(round_number, value, n + increment, increment + 1)
    end
  end
end
