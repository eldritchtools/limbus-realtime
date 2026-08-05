defmodule LimbusRealtime.Realtime.Rooms do
  alias LimbusRealtime.Realtime.Room

  def ensure_room(room_id) do
    case Registry.lookup(LimbusRealtime.RoomRegistry, room_id) do
      [{pid, _}] ->
        {:ok, pid}

      [] ->
        spec = {Room, room_id: room_id}

        case DynamicSupervisor.start_child(LimbusRealtime.RoomSupervisor, spec) do
          {:ok, pid} ->
            {:ok, pid}

          # Another process created it first
          {:error, {:already_started, pid}} ->
            {:ok, pid}

          error ->
            error
        end
    end
  end
end
