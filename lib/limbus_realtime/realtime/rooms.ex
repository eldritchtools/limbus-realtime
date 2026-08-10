defmodule LimbusRealtime.Realtime.Rooms do
  alias LimbusRealtime.Realtime.Room

  def check_room(room_id) do
    case Registry.lookup(LimbusRealtime.RoomRegistry, room_id) do
      [{_pid, _}] ->
        :ok

      [] ->
        :error
    end
  end

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

  defp generate_room_id do
    alphabet = ~c"ABCDEFGHJKLMNPQRSTUVWXYZ23456789"

    for _ <- 1..4, into: "" do
      <<Enum.random(alphabet)>>
    end
  end

  def create_room(type) do
    id = generate_room_id()
    room_id = "#{type}:#{id}"

    case Registry.lookup(LimbusRealtime.RoomRegistry, room_id) do
      [] ->
        {:ok, _} = ensure_room(room_id)
        {:ok, room_id}

      _ ->
        create_room(type)
    end
  end
end
