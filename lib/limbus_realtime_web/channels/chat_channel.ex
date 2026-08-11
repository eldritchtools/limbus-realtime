defmodule LimbusRealtimeWeb.ChatChannel do
  use Phoenix.Channel

  alias LimbusRealtime.Realtime.Components.Chat.Effects
  alias LimbusRealtime.Realtime.Room

  @impl true
  def join("chat:" <> room_id, payload, socket) do
    name = payload["display_name"] |> to_string() |> String.trim()

    user = %{
      connection_id: socket.assigns.connection.id,
      participant_id: "#{payload["client_id"]}:#{name}",
      display_name: name,
      is_developer: LimbusRealtimeWeb.SpecialUsers.is_developer(payload["client_id"])
    }

    socket =
      socket
      |> assign(:user, user)

    payload = Map.put(payload, :user, user)

    case Room.handle_component_action(room_id, :chat, :initialize, payload, socket) do
      {:ok, effects, room_state} ->
        send(self(), {:execute_effects, effects, room_state})
        {:ok, socket}

      {:error, reason} ->
        {:error, %{reason: reason}}
    end
  end

  @impl true
  def terminate(_reason, socket) do
    case Room.handle_component_action(
           room_id(socket),
           :chat,
           :terminate,
           %{user: socket.assigns.user},
           socket
         ) do
      {:ok, effects, room_state} ->
        Effects.execute(effects, socket, room_state, room_state.components.chat)
        :ok

      {:error, reason} ->
        {:error, %{reason: reason}}
    end
  end

  @impl true
  def handle_in("send_message", payload, socket) do
    payload = Map.put(payload, :user, socket.assigns.user)

    case Room.handle_component_action(
           room_id(socket),
           :chat,
           :send_message,
           payload,
           socket
         ) do
      {:ok, effects, room_state} ->
        Effects.execute(effects, socket, room_state, room_state.components.chat)
        {:reply, :ok, socket}

      {:error, reason} ->
        {:reply, {:error, %{reason: reason}}, socket}
    end
  end

  @impl true
  def handle_in(_event, _payload, socket) do
    {:reply, {:error, %{reason: "unknown_event"}}, socket}
  end

  defp room_id(socket) do
    [_prefix, room_id] =
      String.split(socket.topic, ":", parts: 2)

    room_id
  end

  @impl true
  def handle_info({:execute_effects, effects, room_state}, socket) do
    Effects.execute(effects, socket, room_state, room_state.components.chat)

    {:noreply, socket}
  end
end
