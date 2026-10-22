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

    Enum.each(state.spectators, fn {_client_id, spectator} ->
      send(
        spectator.channel_pid,
        {:push_state, build_snapshot(state, spectator.id)}
      )
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

  def execute({:broadcast_public_status, status}, socket, _room_state, _component_state) do
    Channel.broadcast!(socket, "public_status", %{status: status})
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
             participants: build_participants(state),
             blacklist: MapSet.to_list(state.blacklisted_identities)
           }}
        )
      end
    end)
  end

  def execute(
        {:broadcast_draft_pick, type, item_id, draft_index},
        _socket,
        _room_state,
        state
      ) do
    player_id =
      case Enum.at(state.draft_order, draft_index) do
        "e-" <> id -> String.to_integer(id)
        id -> id
      end

    payload = %{
      player_id: player_id,
      type: type,
      item_id: item_id,
      draft_index: draft_index,
      draft_order: current_draft_order(state)
    }

    next_player_id =
      case Enum.at(payload.draft_order, 0) do
        :blacklist -> nil
        "e-" <> id -> String.to_integer(id)
        id -> id
      end

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

    Enum.each(state.spectators, fn {_client_id, spectator} ->
      send(
        spectator.channel_pid,
        {:push_message, "draft_pick", payload}
      )
    end)
  end

  def execute(
        {:broadcast_draft_pick_skipped, draft_index},
        _socket,
        _room_state,
        state
      ) do
    player_id =
      case Enum.at(state.draft_order, draft_index) do
        "e-" <> id -> String.to_integer(id)
        id -> id
      end

    payload = %{
      player_id: player_id,
      draft_index: draft_index,
      draft_order: current_draft_order(state)
    }

    next_player_id =
      case Enum.at(payload.draft_order, 0) do
        :blacklist -> nil
        "e-" <> id -> String.to_integer(id)
        id -> id
      end

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
          {:push_message, "draft_pick_skipped", payload}
        )
      end
    end)

    Enum.each(state.spectators, fn {_client_id, spectator} ->
      send(
        spectator.channel_pid,
        {:push_message, "draft_pick_skipped", payload}
      )
    end)
  end

  def execute(:broadcast_blacklist_state, socket, _room_state, state) do
    Channel.broadcast_from!(socket, "blacklist_state", %{
      chosen_count: map_size(state.blacklist_votes),
      player_count: map_size(state.participants)
    })

    Channel.push(socket, "blacklist_selected", %{
      chosen_count: map_size(state.blacklist_votes),
      player_count: map_size(state.participants)
    })
  end

  def execute({:broadcast_blacklist_resolved, draft_index}, _socket, _room_state, state) do
    payload = %{
      blacklist: MapSet.to_list(state.blacklisted_identities),
      draft_index: draft_index,
      draft_order: current_draft_order(state)
    }

    next_player_id =
      case Enum.at(payload.draft_order, 0) do
        :blacklist -> nil
        "e-" <> id -> String.to_integer(id)
        id -> id
      end

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
          {:push_message, "blacklist_resolved", payload}
        )
      end
    end)

    Enum.each(state.spectators, fn {_client_id, spectator} ->
      send(
        spectator.channel_pid,
        {:push_message, "blacklist_resolved", payload}
      )
    end)
  end

  def execute({:broadcast_draft_round_complete, draft_index}, _socket, _room_state, state) do
    picks =
      Map.new(state.participants, fn {_client_id, participant} ->
        {participant.player_id,
         case Enum.at(state.draft_order, draft_index) do
           :ego -> participant.ego
           _ -> Enum.at(participant.identities, draft_index)
         end}
      end)

    payload = %{
      type: Enum.at(state.draft_order, draft_index),
      picks: picks,
      draft_index: state.draft_index,
      draft_order: current_draft_order(state)
    }

    Enum.each(state.participants, fn {_client_id, participant} ->
      if participant.connected do
        payload = Map.put(payload, :draft_points, participant.draft_points)

        send(
          participant.channel_pid,
          {:push_message, "draft_round_complete", payload}
        )
      end
    end)

    Enum.each(state.spectators, fn {_client_id, spectator} ->
      send(
        spectator.channel_pid,
        {:push_message, "draft_round_complete", payload}
      )
    end)
  end

  def execute({:send_draft_progress, submitted_count}, _socket, _room_state, state) do
    case Map.get(state.participants, state.host_client_id) do
      %{connected: true, channel_pid: channel_pid} ->
        send(
          channel_pid,
          {:push_message, "draft_progress",
           %{
             chosen_count: submitted_count,
             player_count: map_size(state.participants)
           }}
        )

      _ ->
        :ok
    end
  end

  def execute({:send_draft_successful, type, item_id}, socket, _room_state, _state) do
    Channel.push(socket, "draft_successful", %{
      type: type,
      item_id: item_id
    })
  end

  def execute(:broadcast_round, _socket, _room_state, state) do
    Enum.each(state.participants, fn {_client_id, participant} ->
      if participant.connected do
        send(
          participant.channel_pid,
          {:push_message, "round",
           %{
             round_number: state.round_number,
             round: state.current_round,
             skill_counts: participant.skill_counts,
             ego_used: participant.ego_used
           }}
        )
      end
    end)

    Enum.each(state.spectators, fn {_client_id, spectator} ->
      send(
        spectator.channel_pid,
        {:push_message, "round",
         %{
           round_number: state.round_number,
           round: state.current_round
         }}
      )
    end)
  end

  def execute({:broadcast_skill_chosen, type, item_id, skill}, socket, _room_state, state) do
    if state.mode == :standard do
      Channel.broadcast_from!(socket, "skill_chosen_count", %{
        chosen_count: map_size(state.submissions),
        player_count: map_size(state.participants)
      })
    end

    Channel.push(socket, "skill_selected", %{
      type: type,
      item_id: item_id,
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

  def execute({:send_round_progress, submitted_count}, _socket, _room_state, state) do
    case Map.get(state.participants, state.host_client_id) do
      %{connected: true, channel_pid: channel_pid} ->
        send(
          channel_pid,
          {:push_message, "round_progress",
           %{
             chosen_count: submitted_count,
             player_count: map_size(state.participants)
           }}
        )

      _ ->
        :ok
    end
  end

  def execute(:broadcast_game_finished, socket, _room_state, state) do
    Channel.broadcast!(socket, "finished", %{
      participants: build_participants(state)
    })
  end

  defp current_draft_order(state) do
    if state.mode == :standard do
      player_count = map_size(state.participants)

      state.draft_order
      |> Enum.drop(state.draft_index)
      |> Enum.take(player_count)
    else
      Enum.drop(state.draft_order, state.draft_index)
    end
  end

  defp build_snapshot(state, client_id) do
    spectator? = not Map.has_key?(state.participants, client_id)
    participant = state.participants[client_id]

    case state.phase do
      :setup ->
        %{
          mode: state.mode,
          phase: state.phase,
          player_id: nil,
          is_host: client_id == state.host_client_id,
          is_spectator: spectator?,
          is_public: state.public,
          settings: state.settings,
          participants:
            state.participants
            |> Enum.map(fn {_id, participant} -> participant.display_name end)
        }

      :draft ->
        draft_order = current_draft_order(state)

        %{
          mode: state.mode,
          phase: state.phase,
          player_id: participant && participant.player_id,
          draft_points: participant && participant.draft_points,
          is_host: client_id == state.host_client_id,
          is_spectator: spectator?,
          participants: build_participants(state),
          draft_order: draft_order,
          settings: %{
            rounds: state.settings["rounds"],
            points_per_draft: state.settings["points_per_draft"],
            team_size: state.settings["team_size"],
            ego_draft: state.settings["ego_draft"],
            sp_bias: state.settings["sp_bias"],
            sp: state.settings["sp"]
          },
          chosen_count:
            case Enum.at(draft_order, 0) do
              :blacklist -> map_size(state.blacklist_votes)
              _ -> 0
            end,
          picked:
            if spectator? do
              false
            else
              case Enum.at(draft_order, 0) do
                :identity -> length(participant.identities) > state.draft_index
                :ego -> participant.ego != nil
                :blacklist -> Map.has_key?(state.blacklist_votes, client_id)
                _ -> false
              end
            end,
          blacklist: MapSet.to_list(state.blacklisted_identities)
        }

      :draft_complete ->
        %{
          mode: state.mode,
          phase: state.phase,
          player_id: participant && participant.player_id,
          is_host: client_id == state.host_client_id,
          is_spectator: spectator?,
          participants: build_participants(state),
          skill_counts: participant && participant.skill_counts,
          ego_used: participant && participant.ego_used,
          settings: %{rounds: state.settings["rounds"]}
        }

      :round_select ->
        %{
          mode: state.mode,
          phase: state.phase,
          player_id: participant && participant.player_id,
          is_host: client_id == state.host_client_id,
          is_spectator: spectator?,
          participants: build_participants(state),
          current_round: state.current_round,
          round_number: state.round_number,
          skill_counts: participant && participant.skill_counts,
          ego_used: participant && participant.ego_used,
          settings: %{rounds: state.settings["rounds"]},
          chosen_count: map_size(state.submissions),
          picked: not spectator? && Map.has_key?(state.submissions, client_id)
        }

      :round_reveal ->
        %{
          mode: state.mode,
          phase: state.phase,
          player_id: participant && participant.player_id,
          is_host: client_id == state.host_client_id,
          is_spectator: spectator?,
          participants: build_participants(state),
          current_round: state.current_round,
          round_number: state.round_number,
          skill_counts: participant && participant.skill_counts,
          ego_used: participant && participant.ego_used,
          results: state.results,
          settings: %{rounds: state.settings["rounds"]}
        }

      :finished ->
        %{
          mode: state.mode,
          phase: state.phase,
          player_id: participant && participant.player_id,
          is_host: client_id == state.host_client_id,
          is_spectator: spectator?,
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
        identities: participant.identities,
        ego: participant.ego
      }
    end)
    |> Enum.sort_by(& &1.player_id)
  end
end
