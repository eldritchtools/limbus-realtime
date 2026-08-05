defmodule LimbusRealtimeWeb.UserSocket do
  use Phoenix.Socket

  channel "room:*", LimbusRealtimeWeb.RoomChannel
  channel "chat:*", LimbusRealtimeWeb.ChatChannel

  @impl true
  def connect(_params, socket, _connect_info) do
    connection = %LimbusRealtime.Realtime.Connection{
      id: Base.encode16(:crypto.strong_rand_bytes(16), case: :lower),
      joined_at: DateTime.utc_now()
    }

    socket =
      socket
      |> assign(:connection, connection)

    {:ok, socket}
  end

  @impl true
  def id(_socket), do: nil
end
