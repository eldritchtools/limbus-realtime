defmodule LimbusRealtime.Realtime.PublicRoomRegistry do
  use GenServer

  ## ---------- Client API ----------

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def open(room_id, type, host_name, player_count, max_players) do
    GenServer.call(__MODULE__, {:open, room_id, type, host_name, player_count, max_players})
  end

  def update(room_id, player_count) do
    GenServer.call(__MODULE__, {:update, room_id, player_count})
  end

  def close(room_id) do
    GenServer.call(__MODULE__, {:close, room_id})
  end

  def list(type \\ nil) do
    GenServer.call(__MODULE__, {:list, type})
  end

  ## ---------- Server ----------

  @impl true
  def init(state) do
    {:ok, state}
  end

  @impl true
  def handle_call({:open, room_id, type, host_name, player_count, max_players}, _from, state) do
    room = %{
      room_id: room_id,
      type: type,
      host_name: host_name,
      player_count: player_count,
      max_players: max_players
    }

    state = Map.update(state, type, %{room_id => room}, &Map.put(&1, room_id, room))

    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:update, room_id, player_count}, _from, state) do
    state =
      state
      |> Enum.reduce(%{}, fn {type, rooms}, acc ->
        rooms =
          case Map.get(rooms, room_id) do
            nil ->
              rooms

            room ->
              Map.put(rooms, room_id, %{room | player_count: player_count})
          end

        Map.put(acc, type, rooms)
      end)
      |> remove_empty_types()

    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:close, room_id}, _from, state) do
    state =
      state
      |> Enum.reduce(%{}, fn {type, rooms}, acc ->
        Map.put(acc, type, Map.delete(rooms, room_id))
      end)
      |> remove_empty_types()

    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:list, type}, _from, state) do
    rooms =
      case type do
        nil ->
          state
          |> Map.values()
          |> Enum.flat_map(&Map.values/1)

        type ->
          state
          |> Map.get(type, %{})
          |> Map.values()
      end

    {:reply, rooms, state}
  end

  ## ---------- Helpers ----------

  defp remove_empty_types(state) do
    Map.reject(state, fn {_type, rooms} -> map_size(rooms) == 0 end)
  end
end
