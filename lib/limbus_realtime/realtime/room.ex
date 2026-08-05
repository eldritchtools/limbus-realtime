defmodule LimbusRealtime.Realtime.Room do
  use GenServer

  @components %{
    chat: LimbusRealtime.Realtime.Components.Chat.Component,
    quiz: LimbusRealtime.Realtime.Components.Quiz.Component
  }

  ## ---------- Client API ----------

  def start_link(opts) do
    room_id = Keyword.fetch!(opts, :room_id)

    GenServer.start_link(__MODULE__, room_id, name: via(room_id))
  end

  def join(room_id, connection) do
    GenServer.call(via(room_id), {:join, connection})
  end

  def leave(room_id, connection_id) do
    GenServer.call(via(room_id), {:leave, connection_id})
  end

  def member?(room_id, connection_id) do
    GenServer.call(via(room_id), {:member?, connection_id})
  end

  def handle_component_action(room_id, component, action, payload, socket) do
    GenServer.call(
      via(room_id),
      {:handle_component_action, component, action, payload, socket}
    )
  end

  def get_component_state(room_id, component) do
    with_room(room_id, fn pid ->
      GenServer.call(pid, {:get_component_state, component})
    end)
  end

  ## ---------- Server ----------

  @impl true
  def init(room_id) do
    state = %{
      id: room_id,
      empty_window:
        :timer.minutes(
          case room_id do
            "global:lobby" -> 30
            _ -> 5
          end
        ),
      shutdown_timer: nil,
      connections: %{},
      components: %{}
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:join, connection}, _from, state) do
    connections = Map.put(state.connections, connection.id, connection)

    if state.shutdown_timer do
      Process.cancel_timer(state.shutdown_timer)
    end

    {:reply, :ok, %{state | connections: connections, shutdown_timer: nil}}
  end

  @impl true
  def handle_call({:leave, connection_id}, _from, state) do
    connections = Map.delete(state.connections, connection_id)

    state =
      if map_size(connections) == 0 do
        timer =
          Process.send_after(
            self(),
            :shutdown_if_empty,
            state.empty_window
          )

        %{state | shutdown_timer: timer}
      else
        state
      end

    {:reply, :ok, %{state | connections: connections}}
  end

  @impl true
  def handle_call({:member?, connection_id}, _from, state) do
    {:reply, Map.has_key?(state.connections, connection_id), state}
  end

  @impl true
  def handle_call({:handle_component_action, component, action, payload, socket}, _from, state) do
    connection = socket.assigns.connection

    case rate_limit(connection.id, component, action) do
      :allow ->
        is_valid =
          case action do
            :terminate -> true
            _ -> Map.has_key?(state.connections, connection.id)
          end

        if is_valid do
          component_state =
            case Map.get(state.components, component) do
              nil ->
                @components[component].initial_state()

              component_state ->
                component_state
            end

          component_module = @components[component]

          case apply(component_module, action, [payload, connection, component_state]) do
            {:ok, new_component_state, effects} ->
              state = put_in(state.components[component], new_component_state)
              {:reply, {:ok, effects, state}, state}

            {:error, reason} ->
              {:reply, {:error, reason}, state}
          end
        else
          {:reply, {:error, "not_in_room"}, state}
        end

      :deny ->
        {:reply, {:error, "deny"}, state}
    end
  end

  @impl true
  def handle_call({:get_component_state, component}, _from, state) do
    if Map.has_key?(state.components, component) do
      {:reply, {:ok, Map.get(state.components, component)}, state}
    else
      {:reply, {:error, "component_not_in_room"}, state}
    end
  end

  @impl true
  def handle_info(:shutdown_if_empty, state) do
    if map_size(state.connections) == 0 do
      {:stop, :normal, state}
    else
      {:noreply, %{state | shutdown_timer: nil}}
    end
  end

  ## ---------- Registry ----------

  defp via(room_id) do
    {:via, Registry, {LimbusRealtime.RoomRegistry, room_id}}
  end

  ## ---------- Helpers ----------

  defp with_room(room_id, fun) do
    case Registry.lookup(LimbusRealtime.RoomRegistry, room_id) do
      [{pid, _}] ->
        fun.(pid)

      [] ->
        {:error, :room_not_found}
    end
  end

  defp fetch_rate_limits(component, action) do
    Application.fetch_env!(:limbus_realtime, :rate_limits)
    |> Map.get({component, action})
  end

  defp rate_limit(connection_id, component, action) do
    case fetch_rate_limits(component, action) do
      nil ->
        :allow

      {window_ms, limit} ->
        case LimbusRealtime.RateLimit.hit(
               "#{connection_id}:#{component}:#{action}",
               window_ms,
               limit
             ) do
          {:allow, _count} ->
            :allow

          {:deny, _limit} ->
            :deny
        end
    end
  end
end
