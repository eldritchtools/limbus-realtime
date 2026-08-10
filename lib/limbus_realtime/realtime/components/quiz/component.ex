defmodule LimbusRealtime.Realtime.Components.Quiz.Component do
  alias LimbusRealtime.Realtime.Components.Quiz.State

  def initial_state do
    %State{}
  end

  def initialize(payload, _connection, state) do
    with {:ok, user} <- validate_user(payload.user) do
      cond do
        Map.has_key?(state.participants, user.client_id) ->
          state =
            update_in(state.participants[user.client_id], fn participant ->
              %{participant | connected: true, channel_pid: user.channel_pid}
            end)

          {:ok, state, [{:send_state, user.client_id}]}

        state.phase == :setup ->
          participant = %{
            id: user.client_id,
            display_name: user.display_name,
            score: 0,
            connected: true,
            channel_pid: user.channel_pid
          }

          state =
            state
            |> assign_host(user.client_id, payload["settings"])
            |> put_in([Access.key!(:participants), participant.id], participant)

          {:ok, state,
           [{:send_state, participant.id}, {:broadcast_joined, participant.display_name}]}

        true ->
          {:error, "quiz_in_progress"}
      end
    end
  end

  defp assign_host(%State{host_client_id: nil} = state, client_id, initial_settings) do
    %{state | host_client_id: client_id, settings: initial_settings}
  end

  defp assign_host(state, _, _), do: state

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

  def change_settings(payload, _connection, state) do
    with :ok <- check_host(payload, state),
         :ok <- check_phase(:setup, state) do
      state = %{state | settings: payload["settings"]}

      {:ok, state, [:broadcast_settings]}
    else
      {:error, reason} ->
        {:error, reason}
    end
  end

  def start_game(payload, _connection, state) do
    with :ok <- check_host(payload, state),
         :ok <- check_phase(:setup, state) do
      state = %{
        state
        | phase: :guessing,
          current_question: payload["question"],
          current_answer: payload["answer"],
          question_number: 1,
          participants:
            Map.new(state.participants, fn {k, v} ->
              {k, %{v | score: 0}}
            end),
          submissions: %{}
      }

      {:ok, state, [:broadcast_question]}
    else
      {:error, reason} ->
        {:error, reason}
    end
  end

  def submit_answer(payload, _connection, state) do
    with :ok <- check_phase(:guessing, state),
         :ok <- check_participant(payload, state) do
      state = %{
        state
        | submissions: Map.put(state.submissions, payload.user.client_id, payload["answer"])
      }

      {:ok, state, [:broadcast_answer_count, {:confirm_submission, payload["answer"]}]}
    else
      {:error, reason} ->
        {:error, reason}
    end
  end

  def end_round(payload, _connection, state) do
    with :ok <- check_host(payload, state),
         :ok <- check_phase(:guessing, state) do
      state = %{
        state
        | phase: :reveal,
          participants:
            Map.new(state.participants, fn {k, v} ->
              if state.submissions[v.id] === state.current_answer do
                {k, %{v | score: v.score + 1}}
              else
                {k, v}
              end
            end)
      }

      {:ok, state, [:broadcast_reveal]}
    else
      {:error, reason} ->
        {:error, reason}
    end
  end

  def next_round(payload, _connection, state) do
    with :ok <- check_host(payload, state),
         :ok <- check_phase(:reveal, state) do
      state = %{
        state
        | phase: :guessing,
          current_question: payload["question"],
          current_answer: payload["answer"],
          question_number: state.question_number + 1,
          submissions: %{}
      }

      {:ok, state, [:broadcast_question]}
    else
      {:error, reason} ->
        {:error, reason}
    end
  end

  def end_game(payload, _connection, state) do
    with :ok <- check_host(payload, state),
         :ok <- check_phase(:reveal, state) do
      state = %{
        state
        | phase: :finished
      }

      {:ok, state, [:broadcast_final_scoreboard]}
    else
      {:error, reason} ->
        {:error, reason}
    end
  end

  def return_to_setup(payload, _connection, state) do
    with :ok <- check_host(payload, state),
         :ok <- check_phase(:finished, state) do
      participants =
        state.participants
        |> Enum.filter(fn {_id, participant} -> participant.connected end)
        |> Map.new(fn {id, participant} ->
          {id, %{participant | score: 0}}
        end)

      state = %{
        state
        | phase: :setup,
          participants: participants,
          submissions: %{},
          current_question: nil,
          current_answer: nil,
          question_number: 0
      }

      {:ok, state, [:broadcast_setup]}
    else
      {:error, reason} ->
        {:error, reason}
    end
  end

  def terminate(payload, _connection, state) do
    client_id = payload.user.client_id

    {state, effects} =
      case state.phase do
        x when x in [:setup, :finished] ->
          case Map.pop(state.participants, client_id) do
            {nil, _participants} ->
              {state, []}

            {participant, participants} ->
              state = %{state | participants: participants}
              {state, [{:broadcast_left, participant.display_name}]}
          end

        _ ->
          if Map.has_key?(state.participants, client_id) do
            {update_in(state.participants[client_id], fn participant ->
               %{participant | connected: false, channel_pid: nil}
             end), []}
          else
            {state, []}
          end
      end

    {:ok, state, effects}
  end

  defp check_host(payload, state) do
    if payload.user.client_id === state.host_client_id do
      :ok
    else
      {:error, "host_only_action"}
    end
  end

  defp check_phase(phase, state) do
    if state.phase == phase do
      :ok
    else
      {:error, "invalid_phase"}
    end
  end

  defp check_participant(payload, state) do
    if Map.has_key?(state.participants, payload.user.client_id) do
      :ok
    else
      {:error, "not_a_participant"}
    end
  end
end
