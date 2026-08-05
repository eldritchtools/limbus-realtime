defmodule LimbusRealtime.Realtime.Components.Quiz.Effects do
  alias Phoenix.Channel

  def execute(effects, socket, room_state, component_state) when is_list(effects) do
    Enum.each(effects, &execute(&1, socket, room_state, component_state))
  end

  def execute({:send_state, participant_id}, socket, _room_state, component_state) do
    Channel.push(socket, "state", build_snapshot(component_state, participant_id))
  end

  defp build_snapshot(state, client_id) do
    %{
      phase: state.phase,
      is_host: client_id == state.host_client_id,
      participants: Map.values(state.participants),
      submission_count: map_size(state.submissions),
      current_question: state.current_question,
      submission: Map.get(state.submissions, client_id)
    }
  end
end
