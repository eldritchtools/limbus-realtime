defmodule LimbusRealtimeWeb.HealthController do
  use LimbusRealtimeWeb, :controller

  def index(conn, _params) do
    json(conn, %{
      status: "ok"
    })
  end
end
