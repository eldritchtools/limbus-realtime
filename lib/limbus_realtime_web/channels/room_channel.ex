defmodule LimbusRealtimeWeb.RoomChannel do
  use Phoenix.Channel

  alias LimbusRealtime.Realtime.Room
  alias LimbusRealtime.Realtime.Rooms

  @impl true
  def join("room:" <> room_id, _payload, socket) do
    {:ok, _} = Rooms.ensure_room(room_id)

    :ok = Room.join(room_id, socket.assigns.connection)

    socket =
      socket
      |> assign(:room_id, room_id)

    {:ok, socket}
  end

  @impl true
  def handle_in("leave", _payload, socket) do
    :ok =
      Room.leave(
        socket.assigns.room_id,
        socket.assigns.connection.id
      )

    {:stop, :normal, :ok, socket}
  end

  @impl true
  def terminate(_reason, socket) do
    Room.leave(
      socket.assigns.room_id,
      socket.assigns.connection.id
    )

    :ok
  end
end
