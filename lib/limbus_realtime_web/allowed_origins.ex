defmodule LimbusRealtimeWeb.AllowedOrigins do
  def list do
    case Mix.env() do
      :dev -> ["http://localhost:3000"]
      _ -> ["https://eldritchtools.com"]
    end
  end
end
