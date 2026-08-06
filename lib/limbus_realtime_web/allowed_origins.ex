defmodule LimbusRealtimeWeb.AllowedOrigins do
  def list do
    case Mix.env() do
      :dev ->
        [
          "http://localhost:3000"
        ]

      :prod ->
        [
          "https://limbus.eldritchtools.com"
        ]

      :test ->
        []
    end
  end
end
