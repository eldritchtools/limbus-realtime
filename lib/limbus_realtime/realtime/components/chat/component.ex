defmodule LimbusRealtime.Realtime.Components.Chat.Component do
  alias LimbusRealtime.Realtime.Components.Chat.State

  def initial_state do
    %State{}
  end

  def initialize(payload, _connection, state) do
    case validate_user(payload.user) do
      {:ok, user} ->
        now = DateTime.utc_now()
        state = %{state | history: prune_history(state.history, now)}

        {state, effects} = add_connection(state, user)
        {:ok, state, [{:send_history, state.history} | effects]}

      {:error, error} ->
        {:error, error}
    end
  end

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

  defp add_connection(state, user) do
    {participant, effects} =
      case Map.get(state.participants, user.participant_id) do
        nil ->
          participant = %{
            id: user.participant_id,
            display_name: user.display_name,
            connection_count: 1
          }

          {participant, [{:broadcast_system, :joined, %{participant: participant}}]}

        participant ->
          {
            %{participant | connection_count: participant.connection_count + 1},
            []
          }
      end

    connection = %{
      participant_id: participant.id
    }

    state = %{
      state
      | participants: Map.put(state.participants, participant.id, participant),
        connections: Map.put(state.connections, user.connection_id, connection)
    }

    {state, effects}
  end

  def terminate(payload, _connection, state) do
    case remove_connection(state, payload.user.connection_id) do
      {:ok, state, effects} ->
        {:ok, state, effects}

      {:error, error} ->
        {:error, error}
    end
  end

  defp remove_connection(state, connection_id) do
    case Map.get(state.connections, connection_id) do
      nil ->
        {:error, "connection_not_found"}

      connection ->
        participant = Map.fetch!(state.participants, connection.participant_id)

        {participants, effects} =
          case participant.connection_count do
            1 ->
              {
                Map.delete(state.participants, participant.id),
                [{:broadcast_system, :left, %{participant: participant}}]
              }

            _ ->
              {
                Map.put(
                  state.participants,
                  participant.id,
                  %{participant | connection_count: participant.connection_count - 1}
                ),
                []
              }
          end

        {
          :ok,
          %{
            state
            | connections: Map.delete(state.connections, connection_id),
              participants: participants
          },
          effects
        }
    end
  end

  def send_message(payload, _connection, state) do
    with {:ok, text} <- validate_message(payload) do
      now = DateTime.utc_now()

      message = build_message(text, payload.user, now)
      state = add_message(state, message, now)

      {:ok, state, [{:broadcast_message, message}]}
    else
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp add_message(state, message, now) do
    history =
      state.history
      |> prune_history(now)
      |> Kernel.++([message])
      |> Enum.take(-State.history_limit())

    %{state | history: history}
  end

  defp prune_history(history, now) do
    cutoff = DateTime.add(now, -State.history_window_minutes() * 60, :second)

    Enum.filter(history, fn message ->
      DateTime.compare(message.sent_at, cutoff) != :lt
    end)
  end

  defp build_message(text, user, now) do
    %{
      id: Base.encode16(:crypto.strong_rand_bytes(16), case: :lower),
      text: text,
      display_name: user.display_name,
      participant_id: user.participant_id,
      sent_at: now
    }
  end

  defp validate_message(%{"text" => text}) when is_binary(text) do
    text = String.trim(text)

    cond do
      text == "" ->
        {:error, "empty_message"}

      String.length(text) > 2000 ->
        {:error, "message_too_long"}

      true ->
        {:ok, text}
    end
  end

  defp validate_message(_) do
    {:error, "invalid_payload"}
  end
end
