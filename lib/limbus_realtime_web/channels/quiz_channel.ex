defmodule LimbusRealtimeWeb.QuizChannel do
  use Phoenix.Channel

  alias LimbusRealtime.Realtime.Components.Quiz.Effects
  alias LimbusRealtime.Realtime.Room

  @events %{
    "change_settings" => :change_settings,
    "start_game" => :start_game,
    "submit_answer" => :submit_answer,
    "end_round" => :end_round,
    "next_round" => :next_round,
    "end_game" => :end_game,
    "return_to_setup" => :return_to_setup
  }

  @impl true
  def join("quiz:" <> room_id, payload, socket) do
    name = payload["display_name"] |> to_string() |> String.trim()

    user = %{
      connection_id: socket.assigns.connection.id,
      client_id: payload["client_id"],
      display_name: name,
      channel_pid: self()
    }

    socket =
      socket
      |> assign(:user, user)

    payload = Map.put(payload, :user, user)

    case Room.handle_component_action(room_id, :quiz, :initialize, payload, socket) do
      {:ok, effects, room_state} ->
        send(self(), {:execute_effects, effects, room_state})
        {:ok, socket}

      {:error, reason} ->
        {:error, %{reason: reason}}
    end
  end

  @impl true
  def terminate(_reason, socket) do
    if Map.get(socket.assigns, :user) do
      case handle_quiz_action(:terminate, %{user: socket.assigns.user}, socket) do
        {:ok, _socket} ->
          :ok

        {:error, reason} ->
          {:error, %{reason: reason}}
      end
    else
      {:error, %{reason: "refused"}}
    end
  end

  @impl true
  def handle_in(event, payload, socket) do
    case @events[event] do
      nil ->
        {:reply, {:error, %{reason: "unknown_event"}}, socket}

      action ->
        case handle_quiz_action(action, payload, socket) do
          {:ok, socket} ->
            {:reply, :ok, socket}

          {:error, reason} ->
            {:reply, {:error, %{reason: reason}}, socket}
        end
    end
  end

  defp room_id(socket) do
    [_prefix, room_id] =
      String.split(socket.topic, ":", parts: 2)

    room_id
  end

  defp handle_quiz_action(event, payload, socket) do
    payload = Map.put(payload, :user, socket.assigns.user)

    case Room.handle_component_action(
           room_id(socket),
           :quiz,
           event,
           payload,
           socket
         ) do
      {:ok, effects, room_state} ->
        Effects.execute(effects, socket, room_state, room_state.components.quiz)
        {:ok, socket}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def handle_info({:execute_effects, effects, room_state}, socket) do
    Effects.execute(effects, socket, room_state, room_state.components.quiz)

    {:noreply, socket}
  end

  @impl true
  def handle_info({:push_state, payload}, socket) do
    push(socket, "state", payload)
    {:noreply, socket}
  end
end
