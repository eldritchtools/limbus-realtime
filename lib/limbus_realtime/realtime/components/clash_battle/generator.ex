defmodule LimbusRealtime.Realtime.Components.ClashBattle.Generator do
  alias LimbusRealtime.Realtime.Components.ClashBattle.StatusData

  defp random(min, max) do
    Enum.random(min..max)
  end

  defp random_skewed(min, max, exponent, direction) do
    r = :rand.uniform()

    r =
      case direction do
        :low -> :math.pow(r, exponent)
        :high -> 1 - :math.pow(r, exponent)
      end

    min + round(r * (max - min))
  end

  defp random_low(min, max, scale \\ 2) do
    random_skewed(min, max, scale, :low)
  end

  defp random_high(min, max, scale \\ 2) do
    random_skewed(min, max, scale, :high)
  end

  defp random_mid(min, max) do
    round((random(min, max) + random(min, max)) / 2)
  end

  defp random_sp(min, max, bias) when bias < 0 do
    random_skewed(min, max, 1 + abs(bias) / 2, :low)
  end

  defp random_sp(min, max, bias) when bias > 0 do
    random_skewed(min, max, 1 + bias / 2, :high)
  end

  defp random_sp(min, max, 0) do
    Enum.random(min..max)
  end

  defp generate_statuses(settings) do
    count = random(Enum.at(settings["num_status"], 0), Enum.at(settings["num_status"], 1))

    statuses =
      StatusData.all()
      |> Enum.shuffle()
      |> Enum.take(count)

    Map.new(statuses, fn {status, data} ->
      {status, generate_status(data)}
    end)
  end

  defp generate_status(data) do
    data
    |> Enum.filter(fn {key, _} -> key in ["potency", "count"] end)
    |> Map.new(fn {key, config} ->
      field =
        case key do
          "potency" -> :potency
          "count" -> :count
        end

      {field, generate_value(config)}
    end)
  end

  defp generate_value(%{"gen" => "low", "min" => min, "max" => max}) do
    random_low(min, max)
  end

  defp generate_value(%{"gen" => "mid", "min" => min, "max" => max}) do
    random_mid(min, max)
  end

  defp generate_side(settings) do
    %{
      statuses: generate_statuses(settings),
      hp: random_high(Enum.at(settings["hp"], 0), Enum.at(settings["hp"], 1)),
      speed: random_mid(Enum.at(settings["speed"], 0), Enum.at(settings["speed"], 1)),
      sp: random_sp(Enum.at(settings["sp"], 0), Enum.at(settings["sp"], 1), settings["sp_bias"])
    }
  end

  def generate_round(settings) do
    team_bonuses = settings["team_bonuses"] || false

    %{
      self: generate_side(settings),
      target: generate_side(settings),
      unique_statuses_tier: random(0, 3),
      faction_bonus: if(team_bonuses, do: generate_team_bonus(:faction), else: 0),
      keyword_bonus: if(team_bonuses, do: generate_team_bonus(:keyword), else: 0)
    }
  end

  defp generate_team_bonus(:faction) do
    r = :rand.uniform()

    cond do
      r < 0.625 -> 0
      r < 0.875 -> 1
      true -> 2
    end
  end

  defp generate_team_bonus(:keyword) do
    r = :rand.uniform()

    cond do
      r < 0.8125 -> 0
      r < 0.9375 -> 1
      true -> 2
    end
  end
end
