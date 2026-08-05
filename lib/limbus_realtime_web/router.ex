defmodule LimbusRealtimeWeb.Router do
  use LimbusRealtimeWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/api", LimbusRealtimeWeb do
    pipe_through :api

    get "/health", HealthController, :index
    get "/presence", PresenceController, :index
  end
end
