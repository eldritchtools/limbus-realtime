defmodule LimbusRealtimeWeb.PublicRoomsController do
  use LimbusRealtimeWeb, :controller

  alias LimbusRealtime.Realtime.PublicRoomRegistry

  @room_types %{
    "clash_battle" => :clash_battle,
    "battle_royale" => :battle_royale
  }

  def index(conn, params) do
    rooms =
      case params["type"] do
        nil ->
          PublicRoomRegistry.list()

        type ->
          case Map.fetch(@room_types, type) do
            {:ok, type_atom} -> PublicRoomRegistry.list(type_atom)
            :error -> []
          end
      end

    json(conn, %{rooms: Enum.map(rooms, &serialize_room/1)})
  end

  defp serialize_room(room) do
    %{
      room_id: room.room_id,
      type: Atom.to_string(room.type),
      host_name: room.host_name,
      player_count: room.player_count,
      max_players: room.max_players
    }
  end
end
