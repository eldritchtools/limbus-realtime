defmodule LimbusRealtimeWeb.RoomChannel do
  use Phoenix.Channel

  alias LimbusRealtime.Realtime.Room
  alias LimbusRealtime.Realtime.Rooms

  @impl true
  def join("room:" <> room_id, _payload, socket) do
    [type, id] = String.split(room_id, ":", parts: 2)

    room_id =
      case {type, id} do
        {"global", "lobby"} ->
          {:ok, _} = Rooms.ensure_room(room_id)
          room_id

        {type, "new"} ->
          {:ok, id} = Rooms.create_room(type)
          id

        {_type, _id} ->
          case Rooms.check_room(room_id) do
            :ok -> room_id
            :error -> nil
          end
      end

    case room_id do
      nil ->
        {:error, %{reason: "room_not_found"}}

      _ ->
        :ok = Room.join(room_id, socket.assigns.connection)

        socket =
          socket
          |> assign(:room_id, room_id)

        {:ok, %{room_id: room_id}, socket}
    end
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
    case Map.get(socket.assigns, :room_id) do
      nil ->
        :ok

      room_id ->
        Room.leave(
          room_id,
          socket.assigns.connection.id
        )

        :ok
    end
  end
end
