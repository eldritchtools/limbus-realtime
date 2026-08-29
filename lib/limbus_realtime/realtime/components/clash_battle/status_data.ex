defmodule LimbusRealtime.Realtime.Components.ClashBattle.StatusData do
  @data_path :limbus_realtime
             |> :code.priv_dir()
             |> Path.join("data/statuses.json")

  @statuses @data_path
            |> File.read!()
            |> Jason.decode!()

  def all, do: @statuses
end
