defmodule LimbusRealtime.Realtime.Components.ClashBattle.Simulator do
  alias LimbusRealtime.Realtime.Components.ClashBattle.StatusData

  def simulate_round(round, submissions, identity_data) do
    results =
      Map.new(submissions, fn {client_id, %{identity_id: identity_id, skill: skill}} ->
        identity = identity_data |> Map.fetch!(identity_id)
        skill_data = identity |> Map.fetch!(to_string(skill))
        status_data = identity |> Map.get("statuses", [])

        {clash_value, coins} = calculate_skill_clash(skill_data, round, status_data)
        {client_id, %{clash_value: clash_value, coins: coins}}
      end)

    highest = results |> Map.values() |> Enum.map(& &1.clash_value) |> Enum.max()

    Map.new(results, fn {client_id, result} ->
      {client_id, Map.put(result, :points, if(result.clash_value == highest, do: 1, else: 0))}
    end)
  end

  defp calculate_skill_clash(skill, round, status_data) do
    unique_statuses =
      status_data
      |> Enum.map(fn status -> {status["id"], Enum.at(status["values"], round.unique_statuses_tier)} end)
      |> Enum.into(%{})

    modifiers =
      (skill["conditionals"] || [])
      |> Enum.map(&evaluate_conditional(&1, round.self, round.target, unique_statuses))

    base = skill["base"] + modifier_sum(modifiers, "base")
    coin = skill["coin"] + modifier_sum(modifiers, "coin")
    clash = modifier_sum(modifiers, "clash")

    coins = Enum.map(1..skill["coins"], fn _ -> :rand.uniform(100) <= 50 + round.self.sp end)

    offense = modifier_sum(modifiers, "offense-level")

    clash_value = base + clash + div((skill["levelCorrection"] + offense), 3) + Enum.count(coins, & &1) * coin
    {clash_value, coins}
  end

  defp modifier_sum(modifiers, target) do
    modifiers
    |> Enum.filter(fn {modifier_target, _} -> modifier_target == target end)
    |> Enum.map(fn {_, value} -> value end)
    |> Enum.sum()
  end

  defp evaluate_conditional(%{"type" => "status"} = conditional, self, target, unique_statuses) do
    total =
      Enum.sum(
        Enum.map(conditional["status"], fn status ->
          case status["owner"] do
            "unique" ->
              unique_statuses[status["status"]] || 0

            owner ->
              side = if owner == "self", do: self, else: target

              field =
                case status["type"] do
                  "Potency" -> :potency
                  "Count" -> :count
                end

              side.statuses[status["status"]][field] || 0
          end
        end)
      )

    {conditional["target"],
     min(div(total, conditional["per"]) * conditional["value"], conditional["max"])}
  end

  defp evaluate_conditional(
         %{"type" => "status-individual"} = conditional,
         self,
         target,
         unique_statuses
       ) do
    total =
      Enum.sum(
        Enum.map(conditional["status"], fn status ->
          value =
            case status["owner"] do
              "unique" ->
                unique_statuses[status["status"]] || 0

              owner ->
                side = if owner == "self", do: self, else: target

                field =
                  case status["type"] do
                    "Potency" -> :potency
                    "Count" -> :count
                  end

                side.statuses[status["status"]][field] || 0
            end

          div(value, status["per"])
        end)
      )

    {
      conditional["target"],
      min(total * conditional["value"], conditional["max"])
    }
  end

  defp evaluate_conditional(
         %{"type" => "status-optional-condition"} = conditional,
         self,
         target,
         unique_statuses
       ) do
    total =
      Enum.sum(
        Enum.map(conditional["status"], fn status ->
          case status["owner"] do
            "unique" ->
              unique_statuses[status["status"]] || 0

            owner ->
              side = if owner == "self", do: self, else: target

              field =
                case status["type"] do
                  "Potency" -> :potency
                  "Count" -> :count
                end

              side.statuses[status["status"]][field] || 0
          end
        end)
      )

    if Map.get(conditional["statusCond"], 0) > 0 do
      {conditional["target"],
       min(div(total, conditional["perCond"]) * conditional["valueCond"], conditional["maxCond"])}
    else
      {conditional["target"],
       min(div(total, conditional["per"]) * conditional["value"], conditional["max"])}
    end
  end

  defp evaluate_conditional(
         %{"type" => "negative-statuses"} = conditional,
         _self,
         target,
         _unique_statuses
       ) do
    count =
      StatusData.all()
      |> Enum.count(fn {status, data} ->
        data.type == "negative" and Map.has_key?(target.statuses, status)
      end)

    value =
      min(
        div(count, conditional["per"]) * conditional["value"],
        conditional["max"]
      )

    {conditional["target"], value}
  end

  defp evaluate_conditional(%{"type" => "always"} = conditional, _self, _target, _unique_statuses) do
    {conditional["target"], conditional["value"]}
  end

  defp evaluate_conditional(
         %{"type" => "missing-hp"} = conditional,
         self,
         target,
         _unique_statuses
       ) do
    side = if conditional["owner"] == "self", do: self, else: target
    missing_hp = 100 - side.hp

    {
      conditional["target"],
      min(
        trunc(missing_hp / (conditional["per"] * 100)) * conditional["value"],
        conditional["max"]
      )
    }
  end

  defp evaluate_conditional(%{"type" => "have-hp"} = conditional, self, target, _unique_statuses) do
    side = if conditional["owner"] == "self", do: self, else: target

    {
      conditional["target"],
      min(
        trunc(side.hp / (conditional["per"] * 100)) * conditional["value"],
        conditional["max"]
      )
    }
  end

  defp evaluate_conditional(
         %{"type" => "spd-fixed"} = conditional,
         self,
         _target,
         _unique_statuses
       ) do
    valid =
      case conditional["mode"] do
        "higher" -> self.speed > conditional["speed"]
        "lower" -> conditional["speed"] > self.speed
      end

    {conditional["target"], if(valid, do: conditional["value"], else: 0)}
  end

  defp evaluate_conditional(%{"type" => "spd-diff"} = conditional, self, target, _unique_statuses) do
    difference =
      case conditional["mode"] do
        "higher" -> self.speed - target.speed
        "lower" -> target.speed - self.speed
      end

    value =
      if difference > 0 do
        min(div(difference, conditional["per"]) * conditional["value"], conditional["max"])
      else
        0
      end

    {conditional["target"], value}
  end

  defp evaluate_conditional(
         %{"type" => "spd-fixed-or-diff-or-status"} = conditional,
         self,
         target,
         unique_statuses
       ) do
    valid =
      case conditional["mode"] do
        "higher" ->
          (self.speed > conditional["speed"] or
             self.speed - target.speed > conditional["per"] or
             unique_statuses[conditional["status"]]) || 0 > 0

        "lower" ->
          (self.speed < conditional["speed"] or
             target.speed - self.speed > conditional["per"] or
             unique_statuses[conditional["status"]]) || 0 > 0
      end

    {conditional["target"], if(valid, do: conditional["value"], else: 0)}
  end

  defp evaluate_conditional(
         %{"type" => "rupture-15-3"} = conditional,
         _self,
         target,
         _unique_statuses
       ) do
    rupture = Map.get(target.statuses, "Burst", %{potency: 0, count: 0})

    value =
      if rupture.potency >= 15 and rupture.count >= 3 do
        conditional["value"]
      else
        0
      end

    {conditional["target"], value}
  end

  defp evaluate_conditional(
         %{"type" => "charge-consume-hp"} = conditional,
         self,
         _target,
         _unique_statuses
       ) do
    charge = self.statuses["Charge"] || %{"count" => 0}
    charge_count = Map.get(charge, "count", 0)

    missing_count = max(conditional["targetCount"] - charge_count, 0)
    required_hp = missing_count * conditional["hpPerCount"]
    valid = charge_count >= conditional["minCount"] and self.hp >= required_hp

    {conditional["target"], if(valid, do: conditional["value"], else: 0)}
  end

  defp evaluate_conditional(
         %{"type" => "charge-check-potency"} = conditional,
         self,
         _target,
         _unique_statuses
       ) do
    charge = self.statuses["Charge"] || %{potency: 0, count: 0}
    charge_potency = Map.get(charge, :potency, 0)
    charge_count = Map.get(charge, :count, 0)

    valid =
      charge_count >= conditional["targetCount"] ||
        (charge_count >= conditional["minCount"] && charge_potency >= conditional["minPotency"])

    {conditional["target"], if(valid, do: conditional["value"], else: 0)}
  end

  defp evaluate_conditional(%{"type" => "sp-fixed"} = conditional, self, target, _unique_statuses) do
    side = if conditional["owner"] == "self", do: self, else: target

    valid =
      case conditional["mode"] do
        "higher" -> side.sp > conditional["sp"]
        "lower" -> side.sp < conditional["sp"]
      end

    {conditional["target"], if(valid, do: conditional["value"], else: 0)}
  end
end
