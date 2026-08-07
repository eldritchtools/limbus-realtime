defmodule LimbusRealtimeWeb.AllowedOrigins do
  def list do
    case Mix.env() do
      :dev ->
        [
          "http://localhost:3000"
        ]

      :prod ->
        [
          "https://limbus.eldritchtools.com",
          "https://deploy-preview-97--limbus-company-tools.netlify.app"
        ]

      :test ->
        []
    end
  end
end
