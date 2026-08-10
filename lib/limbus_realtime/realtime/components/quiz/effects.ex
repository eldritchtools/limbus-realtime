defmodule LimbusRealtime.Realtime.Components.Quiz.Effects do
  alias Phoenix.Channel

  def execute(effects, socket, room_state, component_state) when is_list(effects) do
    Enum.each(effects, &execute(&1, socket, room_state, component_state))
  end

  def execute({:send_state, participant_id}, socket, _room_state, component_state) do
    Channel.push(socket, "state", build_snapshot(component_state, participant_id))
  end

  def execute({:broadcast_joined, display_name}, socket, _room_state, _component_state) do
    Channel.broadcast_from!(socket, "joined", %{display_name: display_name})
  end

  def execute({:broadcast_left, display_name}, socket, _room_state, _component_state) do
    Channel.broadcast_from!(socket, "left", %{display_name: display_name})
  end

  def execute(:broadcast_settings, socket, _room_state, component_state) do
    Channel.broadcast!(socket, "settings", %{settings: component_state.settings})
  end

  def execute(:broadcast_question, socket, _room_state, component_state) do
    Channel.broadcast!(socket, "question", %{
      current_question: component_state.current_question,
      question_number: component_state.question_number
    })
  end

  def execute(:broadcast_answer_count, socket, _room_state, component_state) do
    Channel.broadcast!(socket, "answer_count", %{
      answer_count: map_size(component_state.submissions),
      participant_count: map_size(component_state.participants)
    })
  end

  def execute({:confirm_submission, submission}, socket, _room_state, _component_state) do
    Channel.push(socket, "submission", %{submission: submission})
  end

  def execute(:broadcast_reveal, _socket, _room_state, component_state) do
    shared = %{
      phase: component_state.phase,
      current_answer: component_state.current_answer,
      correct_participants:
        component_state.participants
        |> Enum.filter(fn {id, _participant} ->
          component_state.submissions[id] == component_state.current_answer
        end)
        |> Enum.map(fn {_id, participant} -> participant.display_name end),
      scoreboard: build_scoreboard(component_state)
    }

    Enum.each(component_state.participants, fn {_id, participant} ->
      if participant.connected do
        payload =
          shared
          |> Map.put(:score, participant.score)

        send(participant.channel_pid, {:push_state, payload})
      end
    end)
  end

  def execute(:broadcast_final_scoreboard, _socket, _room_state, component_state) do
    shared = %{
      phase: component_state.phase,
      scoreboard: build_scoreboard(component_state)
    }

    Enum.each(component_state.participants, fn {_id, participant} ->
      if participant.connected do
        payload =
          shared
          |> Map.put(:score, participant.score)

        send(participant.channel_pid, {:push_state, payload})
      end
    end)
  end

  def execute(:broadcast_setup, socket, _room_state, component_state) do
    Channel.broadcast!(socket, "state", %{
      phase: component_state.phase,
      settings: component_state.settings,
      participants: Enum.map(component_state.participants, fn {_k, v} -> v.display_name end),
      score: 0
    })
  end

  defp build_snapshot(state, client_id) do
    case state.phase do
      :setup ->
        %{
          phase: state.phase,
          is_host: client_id == state.host_client_id,
          settings: state.settings,
          participants: Enum.map(state.participants, fn {_k, v} -> v.display_name end)
        }

      :guessing ->
        %{
          phase: state.phase,
          is_host: client_id == state.host_client_id,
          settings: state.settings,
          current_question: state.current_question,
          question_number: state.question_number,
          submission: Map.get(state.submissions, client_id),
          score: state.participants[client_id].score,
          answer_count: map_size(state.submissions),
          participant_count: map_size(state.participants)
        }

      :reveal ->
        %{
          phase: state.phase,
          is_host: client_id == state.host_client_id,
          settings: state.settings,
          current_question: state.current_question,
          current_answer: state.current_answer,
          question_number: state.question_number,
          submission: Map.get(state.submissions, client_id),
          score: state.participants[client_id].score,
          correct_participants:
            state.participants
            |> Enum.filter(fn {id, _participant} ->
              state.submissions[id] == state.current_answer
            end)
            |> Enum.map(fn {_id, participant} -> participant.display_name end),
          scoreboard: build_scoreboard(state),
          participant_count: map_size(state.participants)
        }

      :finished ->
        %{
          phase: state.phase,
          is_host: client_id == state.host_client_id,
          settings: state.settings,
          score: state.participants[client_id].score,
          scoreboard: build_scoreboard(state)
        }
    end
  end

  defp build_scoreboard(state) do
    state.participants
    |> Enum.map(fn {_id, participant} ->
      %{
        display_name: participant.display_name,
        score: participant.score
      }
    end)
    |> Enum.sort(fn a, b -> a.score > b.score end)
  end
end
