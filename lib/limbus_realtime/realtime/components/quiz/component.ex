defmodule LimbusRealtime.Realtime.Components.Quiz.Component do
  alias LimbusRealtime.Realtime.Components.Quiz.State

  def initial_state do
    %State{}
  end

  def initialize(payload, _connection, state) do
    with {:ok, user} <- validate_user(payload.user),
         :ok <- ensure_joinable(state) do
      participant = %{
        id: user.client_id,
        display_name: user.display_name,
        score: 0
      }

      state =
        state
        |> assign_host(user.client_id)
        |> put_in([Access.key!(:participants), participant.id], participant)

      {:ok, state, [{:send_state, participant.id}]}
    end
  end

  defp ensure_joinable(%State{phase: :setup}), do: :ok
  defp ensure_joinable(_), do: {:error, "quiz_in_progress"}

  defp assign_host(%State{host_client_id: nil} = state, client_id) do
    %{state | host_client_id: client_id}
  end

  defp assign_host(state, _), do: state

  defp validate_user(user) do
    cond do
      String.length(user.display_name) > 100 ->
        {:error, "display_name_too_long"}

      true ->
        name =
          case user.display_name do
            "" -> "Guest"
            value -> value
          end

        {:ok, %{user | display_name: name}}
    end
  end

  def terminate(payload, _connection, state) do
    participant_id = payload.user.client_id
    participants = Map.delete(state.participants, participant_id)
    state = %{state | participants: participants}

    {:ok, state, []}
  end
end
