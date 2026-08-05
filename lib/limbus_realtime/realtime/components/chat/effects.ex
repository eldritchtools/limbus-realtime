defmodule LimbusRealtime.Realtime.Components.Chat.Effects do
  alias Phoenix.Channel

  def execute(effects, socket, room_state, component_state) when is_list(effects) do
    Enum.each(effects, &execute(&1, socket, room_state, component_state))
  end

  def execute({:broadcast_message, message}, socket, _room_state, _component_state) do
    # message = %{message | user: socket.assigns.user}
    Channel.broadcast!(socket, "message", message)
  end

  def execute({:send_history, history}, socket, _room_state, component_state) do
    Channel.push(socket, "history", %{history: history, user_count: map_size(component_state.participants)})
  end

  def execute({:broadcast_system, type, data}, socket, _room_state, component_state) do
    case type do
      :joined ->
        Channel.broadcast!(socket, "system", %{type: :joined, participant: data.participant, user_count: map_size(component_state.participants)})

      :left ->
        Channel.broadcast!(socket, "system", %{type: :left, participant: data.participant, user_count: map_size(component_state.participants)})
    end
  end
end
