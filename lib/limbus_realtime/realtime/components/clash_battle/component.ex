defmodule LimbusRealtime.Realtime.Components.ClashBattle.Component do
  alias LimbusRealtime.Realtime.Components.ClashBattle.State
  alias LimbusRealtime.Realtime.Components.ClashBattle.Generator
  alias LimbusRealtime.Realtime.Components.ClashBattle.Simulator
  alias LimbusRealtime.Realtime.Components.ClashBattle.Modifiers
  alias LimbusRealtime.Realtime.Data.ClashingData

  @max_players 8

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

        state.phase != :setup ->
          {:error, "game_in_progress"}

        map_size(state.participants) >= @max_players ->
          {:error, "room_full"}

        true ->
          participant = %{
            id: user.client_id,
            player_id: nil,
            display_name: user.display_name,
            score: 0,
            identities: [],
            connected: true,
            channel_pid: user.channel_pid,
            skill_counts: [],
            draft_points: 0,
            ego: nil,
            ego_used: false
          }

          state =
            state
            |> assign_host(user.client_id, payload["settings"])
            |> put_in([Access.key!(:participants), participant.id], participant)
            |> Map.update!(:player_order, &(&1 ++ [participant.id]))

          {:ok, state,
           [{:send_state, participant.id}, {:broadcast_joined, participant.display_name}]}
      end
    end
  end

  defp assign_host(%State{host_client_id: nil} = state, client_id, initial_settings) do
    %{state | host_client_id: client_id, settings: initial_settings || %{}}
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
      state = %{state | settings: Map.merge(state.settings, payload["settings"])}

      {:ok, state, [{:broadcast_settings, payload["settings"]}]}
    else
      {:error, reason} ->
        {:error, reason}
    end
  end

  def start_draft(payload, _connection, state) do
    with :ok <- check_host(payload, state),
         :ok <- check_phase(:setup, state) do
      participants =
        state.player_order
        |> Enum.with_index(1)
        |> Map.new(fn {client_id, player_id} ->
          participant = Map.fetch!(state.participants, client_id)

          {client_id,
           %{participant | player_id: player_id, identities: [], score: 0, draft_points: 0}}
        end)

      player_ids =
        state.player_order
        |> Enum.map(&participants[&1].player_id)

      draft_order =
        build_draft_order(
          player_ids,
          state.settings["team_size"],
          state.settings["draft_order"],
          state.settings["ego_draft"]
        )

      state =
        %{
          state
          | phase: :draft,
            participants: participants,
            draft_order: draft_order,
            draft_index: 0,
            picked_identities: MapSet.new(),
            picked_egos: MapSet.new(),
            item_data: %{}
        }
        |> add_draft_points(0)

      {:ok, state, [:broadcast_draft_started]}
    else
      {:error, reason} ->
        {:error, reason}
    end
  end

  def pick_item(payload, _connection, state) do
    with :ok <- check_phase(:draft, state),
         :ok <- check_draft_turn(payload, state),
         {:ok, type, cost} <- check_item(payload["item_id"], payload.user.client_id, state) do
      client_id = payload.user.client_id
      item_id = payload["item_id"]
      draft_index = state.draft_index

      participant = Map.fetch!(state.participants, client_id)

      participants =
        case type do
          :id ->
            put_in(
              state.participants,
              [client_id],
              %{
                participant
                | identities: participant.identities ++ [item_id],
                  draft_points: participant.draft_points - cost
              }
            )

          :ego ->
            put_in(
              state.participants,
              [client_id],
              %{
                participant
                | ego: item_id,
                  draft_points: participant.draft_points - cost
              }
            )
        end

      state =
        case type do
          :id ->
            %{
              state
              | participants: participants,
                picked_identities: MapSet.put(state.picked_identities, item_id),
                draft_index: draft_index + 1
            }

          :ego ->
            %{
              state
              | participants: participants,
                picked_egos: MapSet.put(state.picked_egos, item_id),
                draft_index: draft_index + 1
            }
        end

      if state.draft_index >= length(state.draft_order) do
        state = finish_draft(state)

        {:ok, state, [:broadcast_state]}
      else
        state = state |> add_draft_points(draft_index + 1)
        {:ok, state, [{:broadcast_draft_pick, type, item_id, draft_index}]}
      end
    else
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp add_draft_points(state, draft_index) do
    points = state.settings["points_per_draft"]

    if points do
      {type, player_id} =
        case Enum.at(state.draft_order, draft_index) do
          "e-" <> player_id ->
            {:ego, String.to_integer(player_id)}

          player_id ->
            {:id, player_id}
        end

      {client_id, participant} =
        Enum.find(state.participants, fn {_client_id, participant} ->
          participant.player_id == player_id
        end)

      to_add =
        case type do
          :id -> points
          :ego -> ceil(points / 2) |> trunc()
        end

      participants =
        Map.put(
          state.participants,
          client_id,
          %{participant | draft_points: participant.draft_points + to_add}
        )

      %{state | participants: participants}
    else
      state
    end
  end

  def start_game(payload, _connection, state) do
    with :ok <- check_host(payload, state),
         :ok <- check_phase(:draft_complete, state) do
      state = %{
        state
        | phase: :round_select,
          round_number: 1,
          submissions: %{},
          results: %{}
      }

      state = start_round(state)

      {:ok, state, [:broadcast_round]}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  def select_skill(payload, _connection, state) do
    client_id = payload.user.client_id
    item_id = payload["item_id"]
    skill = payload["skill"]

    with :ok <- check_phase(:round_select, state),
         :ok <- check_participant(payload, state),
         false <- Map.has_key?(state.submissions, client_id),
         {:ok, participant, type, resolved_skill} <-
           resolve_and_consume_skill(
             state.participants[client_id],
             item_id,
             skill,
             state.current_round,
             state.item_data
           ) do
      submission = %{
        type: type,
        item_id: item_id,
        skill: skill,
        resolved_skill: resolved_skill
      }

      state = put_in(state.participants[client_id], participant)
      state = put_in(state.submissions[client_id], submission)

      if map_size(state.submissions) == map_size(state.participants) do
        {:ok, resolve_round(state),
         [{:broadcast_skill_chosen, type, item_id, skill}, :broadcast_round_reveal]}
      else
        {:ok, state, [{:broadcast_skill_chosen, type, item_id, skill}]}
      end
    else
      true ->
        {:error, "already_submitted"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp resolve_and_consume_skill(participant, item_id, skill, round, item_data) do
    case item_data[item_id]["type"] do
      "id" ->
        case participant.skill_counts[item_id] do
          nil ->
            {:error, "invalid_identity"}

          counts ->
            index = skill - 1

            if Enum.at(counts, index, 0) > 0 do
              identity = Map.fetch!(item_data, item_id)
              resolved_skill = Modifiers.resolve_skill(identity, skill, round)

              counts = List.update_at(counts, index, &(&1 - 1))

              participant = %{
                participant
                | skill_counts: Map.put(participant.skill_counts, item_id, counts)
              }

              {:ok, participant, :id, resolved_skill}
            else
              {:error, "skill_unavailable"}
            end
        end

      "ego" ->
        cond do
          participant.ego != item_id ->
            {:error, "invalid_ego"}

          participant.ego_used ->
            {:error, "skill_unavailable"}

          true ->
            ego = Map.fetch!(item_data, item_id)
            resolved_skill = Modifiers.resolve_skill(ego, skill, round)

            participant = %{participant | ego_used: true}
            {:ok, participant, :ego, resolved_skill}
        end
    end
  end

  defp resolve_round(state) do
    results =
      Simulator.simulate_round(
        state.current_round,
        state.submissions,
        state.item_data
      )

    participants =
      Map.new(state.participants, fn {client_id, participant} ->
        {client_id, %{participant | score: participant.score + results[client_id].points}}
      end)

    results =
      Map.new(results, fn {client_id, result} ->
        {state.participants[client_id].player_id, Map.merge(result, state.submissions[client_id])}
      end)

    %{state | phase: :round_reveal, participants: participants, results: results}
  end

  def next_round(payload, _connection, state) do
    with :ok <- check_host(payload, state),
         :ok <- check_phase(:round_reveal, state) do
      if state.round_number >= state.settings["rounds"] do
        {:ok, %{state | phase: :finished}, [:broadcast_game_finished]}
      else
        state = %{
          state
          | phase: :round_select,
            submissions: %{},
            results: %{},
            round_number: state.round_number + 1
        }

        state = start_round(state)

        {:ok, state, [:broadcast_round]}
      end
    else
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp start_round(state) do
    round = Generator.generate_round(state.settings)

    state
    |> Map.put(:current_round, round)
    |> Modifiers.apply_round_start(state.round_number)
  end

  def return_to_setup(payload, _connection, state) do
    with :ok <- check_host(payload, state),
         :ok <- check_phase(:finished, state) do
      participants =
        Map.new(state.participants, fn {client_id, participant} ->
          {client_id,
           %{
             participant
             | player_id: nil,
               score: 0,
               identities: [],
               ego: nil,
               ego_used: false,
               connected: participant.connected
           }}
        end)

      state = %{
        state
        | phase: :setup,
          participants: participants,
          host_client_id: state.host_client_id,
          settings: state.settings,
          draft_order: [],
          draft_index: 0,
          picked_identities: MapSet.new(),
          picked_egos: MapSet.new(),
          item_data: %{},
          round_number: 0,
          current_round: nil,
          submissions: %{},
          results: %{}
      }

      {:ok, state, [:broadcast_state]}
    else
      {:error, reason} -> {:error, reason}
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
              state = %{
                state
                | participants: participants,
                  player_order: List.delete(state.player_order, client_id)
              }

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

  defp finish_draft(state) do
    selected_ids =
      state.picked_identities
      |> MapSet.union(state.picked_egos)
      |> MapSet.to_list()

    participants =
      Map.new(state.participants, fn {client_id, participant} ->
        skill_counts =
          Map.new(participant.identities, fn identity_id ->
            {identity_id, [3, 2, 1, 0]}
          end)

        {client_id, %{participant | skill_counts: skill_counts, ego_used: false, score: 0}}
      end)

    %{
      state
      | phase: :draft_complete,
        participants: participants,
        draft_order: [],
        draft_index: 0,
        round_number: 0,
        item_data: ClashingData.get(selected_ids),
        submissions: %{},
        current_round: nil
    }
  end

  defp build_draft_order(player_ids, team_size, mode, ego_draft) do
    identity_order =
      case mode do
        "snake" ->
          build_snake_draft_order(player_ids, team_size)

        "random" ->
          build_random_draft_order(player_ids, team_size)

        _ ->
          build_cycle_draft_order(player_ids, team_size)
      end

    if ego_draft do
      ego_order =
        case mode do
          "snake" ->
            build_snake_draft_order(player_ids, 1, team_size)

          "random" ->
            build_random_draft_order(player_ids, 1)

          _ ->
            build_cycle_draft_order(player_ids, 1)
        end
        |> Enum.map(&"e-#{&1}")

      identity_order ++ ego_order
    else
      identity_order
    end
  end

  defp build_cycle_draft_order(player_ids, team_size) do
    List.duplicate(player_ids, team_size)
    |> List.flatten()
  end

  defp build_snake_draft_order(player_ids, team_size, offset \\ 0) do
    player_ids
    |> List.duplicate(team_size)
    |> Enum.with_index()
    |> Enum.map(fn {ids, index} ->
      if rem(index + offset, 2) == 0 do
        ids
      else
        Enum.reverse(ids)
      end
    end)
    |> List.flatten()
  end

  defp build_random_draft_order(player_ids, team_size) do
    Enum.map(1..team_size, fn _ ->
      Enum.shuffle(player_ids)
    end)
    |> List.flatten()
  end

  defp check_item(item_id, client_id, state) do
    case state.draft_order |> Enum.at(state.draft_index) do
      "e-" <> _ ->
        check_ego(item_id, client_id, state)

      _ ->
        check_identity(item_id, client_id, state)
    end
  end

  defp check_identity(identity_id, client_id, state) do
    cond do
      not is_binary(identity_id) ->
        {:error, "invalid_identity"}

      MapSet.member?(state.picked_identities, identity_id) ->
        {:error, "identity_already_picked"}

      not ClashingData.has_id?(identity_id) ->
        {:error, "invalid_identity"}

      true ->
        points = state.participants[client_id].draft_points

        if state.settings["points_per_draft"] != 0 do
          identity = ClashingData.get([identity_id])[identity_id]

          cond do
            identity["type"] != "id" ->
              {:error, "invalid_identity"}

            points < identity["points"] ->
              {:error, "not_enough_points"}

            true ->
              {:ok, :id, identity["points"]}
          end
        else
          {:ok, 0}
        end
    end
  end

  defp check_ego(ego_id, client_id, state) do
    cond do
      not is_binary(ego_id) ->
        {:error, "invalid_ego"}

      MapSet.member?(state.picked_egos, ego_id) ->
        {:error, "ego_already_picked"}

      not ClashingData.has_id?(ego_id) ->
        {:error, "invalid_ego"}

      true ->
        points = state.participants[client_id].draft_points

        if state.settings["points_per_draft"] != 0 do
          ego = ClashingData.get([ego_id])[ego_id]

          cond do
            ego["type"] != "ego" ->
              {:error, "invalid_ego"}

            points < ego["points"] ->
              {:error, "not_enough_points"}

            true ->
              {:ok, :ego, ego["points"]}
          end
        else
          {:ok, 0}
        end
    end
  end

  defp check_draft_turn(payload, state) do
    current_client_id =
      state.draft_order
      |> Enum.at(state.draft_index)
      |> then(fn
        "e-" <> player_id -> String.to_integer(player_id)
        player_id -> player_id
      end)
      |> player_client_id(state)

    if payload.user.client_id === current_client_id do
      :ok
    else
      {:error, "not_your_turn"}
    end
  end

  defp player_client_id(player_id, state) do
    Enum.find(state.player_order, fn client_id ->
      state.participants[client_id].player_id == player_id
    end)
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
