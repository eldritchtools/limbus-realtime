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

  defp random_low(min, max) do
    random_skewed(min, max, 3, :low)
  end

  defp random_high(min, max) do
    random_skewed(min, max, 3, :high)
  end

  defp random_mid(min, max) do
    round((random(min, max) + random(min, max)) / 2)
  end

  defp generate_statuses(settings) do
    count = random(Enum.at(settings["num_status"], 0), Enum.at(settings["num_status"], 1))

    statuses =
      StatusData.all()
      |> Enum.filter(fn {_, data} -> data["set"] == "primary" end)
      |> Enum.shuffle()
      |> Enum.take(count)

    statuses =
      if :rand.uniform() <= settings["secondary_status_chance"] do
        case StatusData.all()
             |> Enum.filter(fn {_, data} -> data["set"] == "secondary" end)
             |> Enum.random() do
          {status, data} ->
            [{status, data} | statuses]
        end
      else
        statuses
      end

    Map.new(statuses, fn {status, data} ->
      {status, generate_status(data)}
    end)
  end

  defp generate_status(data) do
    data
    |> Enum.filter(fn {key, _} -> key in ["potency", "count"] end)
    |> Map.new(fn {key, config} ->
      {key, generate_value(config)}
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
      sp: random(Enum.at(settings["sp"], 0), Enum.at(settings["sp"], 1))
    }
  end

  def generate_round(settings) do
    %{
      self: generate_side(settings),
      target: generate_side(settings)
    }
  end
end
