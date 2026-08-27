defmodule LimbusRealtime.Realtime.Components.ClashBattle.Generator do
  @statuses [
    "Burn",
    "Bleed",
    "Tremor",
    "Rupture",
    "Sinking",
    "Poise",
    "Charge"
  ]

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
    random_skewed(min, max, 2, :low)
  end

  defp random_high(min, max) do
    random_skewed(min, max, 2, :high)
  end

  defp random_mid(min, max) do
    round((random(min, max) + random(min, max)) / 2)
  end

  defp generate_statuses(settings) do
    count = random(settings.num_status[0], settings.num_status[1])

    @statuses
    |> Enum.shuffle()
    |> Enum.take(count)
    |> Map.new(fn status ->
      {status,
       %{
         potency: random_low(settings.status_potency[0], settings.status_potency[1]),
         count: random_low(settings.status_count[0], settings.status_count[1])
       }}
    end)
  end

  defp generate_side(settings) do
    %{
      statuses: generate_statuses(settings),
      hp: random_high(settings.hp[0], settings.hp[1]),
      speed: random_mid(settings.speed[0], settings.speed[1]),
      sp: random(settings.sp[0], settings.sp[1])
    }
  end

  def generate_round(settings) do
    %{
      self: generate_side(settings),
      target: generate_side(settings)
    }
  end
end
