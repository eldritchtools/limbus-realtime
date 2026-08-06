# defmodule LimbusRealtimeWeb.AllowedOrigins do
#   def list do
#     case Mix.env() do
#       :dev -> ["http://localhost:3000"]
#       _ -> ["https://limbus.eldritchtools.com"]
#     end
#   end
# end

defmodule LimbusRealtimeWeb.AllowedOrigins do
  def list do
    Application.fetch_env!(:limbus_realtime, :allowed_origins)
  end
end
