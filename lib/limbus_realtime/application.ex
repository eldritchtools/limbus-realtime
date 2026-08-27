defmodule LimbusRealtime.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      LimbusRealtimeWeb.Telemetry,
      {DNSCluster, query: Application.get_env(:limbus_realtime, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: LimbusRealtime.PubSub},
      # Start a worker by calling: LimbusRealtime.Worker.start_link(arg)
      # {LimbusRealtime.Worker, arg},
      # Start to serve requests, typically the last entry
      LimbusRealtimeWeb.Endpoint,
      {Registry, keys: :unique, name: LimbusRealtime.RoomRegistry},
      {DynamicSupervisor, strategy: :one_for_one, name: LimbusRealtime.RoomSupervisor},
      {LimbusRealtime.RateLimit, [clean_period: :timer.minutes(10)]},
      LimbusRealtime.Realtime.Data.ClashingData
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: LimbusRealtime.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    LimbusRealtimeWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
