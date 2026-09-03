defmodule LimbusRealtime.Realtime.Components.ClashBattle.Effects do
  alias Phoenix.Channel

  def execute(effects, socket, room_state, component_state) when is_list(effects) do
    Enum.each(effects, &execute(&1, socket, room_state, component_state))
  end

  def execute({:send_state, participant_id}, socket, _room_state, component_state) do
    Channel.push(socket, "state", build_snapshot(component_state, participant_id))
  end

  def execute(:broadcast_state, _socket, _room_state, state) do
    Enum.each(state.participants, fn {_client_id, participant} ->
      if participant.connected do
        send(
          participant.channel_pid,
          {:push_state, build_snapshot(state, participant.id)}
        )
      end
    end)
  end

  def execute({:broadcast_joined, display_name}, socket, _room_state, _component_state) do
    Channel.broadcast_from!(socket, "joined", %{display_name: display_name})
  end

  def execute({:broadcast_left, display_name}, socket, _room_state, _component_state) do
    Channel.broadcast_from!(socket, "left", %{display_name: display_name})
  end

  def execute({:broadcast_settings, settings}, socket, _room_state, _component_state) do
    Channel.broadcast!(socket, "settings", %{settings: settings})
  end

  def execute(:broadcast_draft_started, _socket, _room_state, state) do
    Enum.each(state.participants, fn {_client_id, participant} ->
      if participant.connected do
        send(
          participant.channel_pid,
          {:push_message, "draft_started",
           %{
             player_id: participant.player_id,
             draft_points: participant.draft_points,
             draft_order: current_draft_order(state),
             participants: build_participants(state)
           }}
        )
      end
    end)
  end

  def execute(
        {:broadcast_draft_pick, identity_id, draft_index},
        _socket,
        _room_state,
        state
      ) do
    player_id = Enum.at(state.draft_order, draft_index)

    payload = %{
      player_id: player_id,
      identity_id: identity_id,
      draft_index: draft_index,
      draft_order: current_draft_order(state)
    }

    next_player_id = Enum.at(payload.draft_order, 0)

    Enum.each(state.participants, fn {_client_id, participant} ->
      if participant.connected do
        payload =
          if participant.player_id == next_player_id do
            Map.put(payload, :draft_points, participant.draft_points)
          else
            payload
          end

        send(
          participant.channel_pid,
          {:push_message, "draft_pick", payload}
        )
      end
    end)
  end

  def execute(:broadcast_round, socket, _room_state, state) do
    Channel.broadcast!(socket, "round", %{
      round_number: state.round_number,
      round: state.current_round
    })
  end

  def execute({:broadcast_skill_chosen, identity_id, skill}, socket, _room_state, state) do
    Channel.broadcast_from!(socket, "skill_chosen_count", %{
      chosen_count: map_size(state.submissions),
      player_count: map_size(state.participants)
    })

    Channel.push(socket, "skill_selected", %{
      identity_id: identity_id,
      skill: skill,
      chosen_count: map_size(state.submissions),
      player_count: map_size(state.participants)
    })
  end

  def execute(:broadcast_round_reveal, socket, _room_state, state) do
    Channel.broadcast!(socket, "round_reveal", %{
      round_number: state.round_number,
      participants: build_participants(state),
      results: state.results
    })
  end

  def execute(:broadcast_game_finished, socket, _room_state, state) do
    Channel.broadcast!(socket, "finished", %{
      participants: build_participants(state)
    })
  end

  defp current_draft_order(state) do
    player_count = map_size(state.participants)

    state.draft_order
    |> Enum.drop(state.draft_index)
    |> Enum.take(player_count)
  end

  defp build_snapshot(state, client_id) do
    participant = Map.fetch!(state.participants, client_id)

    case state.phase do
      :setup ->
        %{
          phase: state.phase,
          player_id: nil,
          is_host: client_id == state.host_client_id,
          settings: state.settings,
          participants:
            state.participants
            |> Enum.map(fn {_id, participant} -> participant.display_name end)
        }

      :draft ->
        %{
          phase: state.phase,
          player_id: participant.player_id,
          draft_points: participant.draft_points,
          is_host: client_id == state.host_client_id,
          participants: build_participants(state),
          draft_order: current_draft_order(state),
          settings: %{rounds: state.settings["rounds"]}
        }

      :draft_complete ->
        %{
          phase: state.phase,
          player_id: participant.player_id,
          is_host: client_id == state.host_client_id,
          participants: build_participants(state),
          skill_counts: participant.skill_counts,
          settings: %{rounds: state.settings["rounds"]}
        }

      :round_select ->
        %{
          phase: state.phase,
          player_id: participant.player_id,
          is_host: client_id == state.host_client_id,
          participants: build_participants(state),
          current_round: state.current_round,
          round_number: state.round_number,
          skill_counts: participant.skill_counts,
          settings: %{rounds: state.settings["rounds"]}
        }

      :round_reveal ->
        %{
          phase: state.phase,
          player_id: participant.player_id,
          is_host: client_id == state.host_client_id,
          participants: build_participants(state),
          current_round: state.current_round,
          round_number: state.round_number,
          skill_counts: participant.skill_counts,
          results: state.results,
          settings: %{rounds: state.settings["rounds"]}
        }

      :finished ->
        %{
          phase: state.phase,
          player_id: participant.player_id,
          is_host: client_id == state.host_client_id,
          participants: build_participants(state)
        }
    end
  end

  defp build_participants(state) do
    state.participants
    |> Enum.map(fn {_id, participant} ->
      %{
        player_id: participant.player_id,
        display_name: participant.display_name,
        score: participant.score,
        identities: participant.identities
      }
    end)
    |> Enum.sort_by(& &1.player_id)
  end
end
