defmodule LimbusRealtimeWeb.PresenceController do
  use LimbusRealtimeWeb, :controller

  alias LimbusRealtime.Realtime.Room

  def index(conn, _params) do
    count =
      case Room.get_component_state("global:lobby", :chat) do
        {:ok, component_state} ->
          map_size(component_state.participants)

        {:error, _reason} ->
          0
      end

    json(conn, %{
      status: "ok",
      rooms: %{
        "global:lobby" => count
      }
    })
  end
end
