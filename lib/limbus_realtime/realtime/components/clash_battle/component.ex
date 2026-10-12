defmodule LimbusRealtime.Realtime.Components.ClashBattle.Component do
  alias LimbusRealtime.Realtime.Components.ClashBattle.State
  alias LimbusRealtime.Realtime.Components.ClashBattle.Generator
  alias LimbusRealtime.Realtime.Components.ClashBattle.Simulator
  alias LimbusRealtime.Realtime.Components.ClashBattle.Modifiers
  alias LimbusRealtime.Realtime.Data.ClashingData

  @max_players %{
    standard: 8,
    battle_royale: 200
  }

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

        map_size(state.participants) >= @max_players[state.mode] ->
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
            |> assign_host(user.client_id, payload["mode"], payload["settings"])
            |> put_in([Access.key!(:participants), participant.id], participant)
            |> Map.update!(:player_order, &(&1 ++ [participant.id]))

          players = map_size(state.participants)

          {state, effect} =
            if players >= @max_players[state.mode] do
              :ok = LimbusRealtime.Realtime.PublicRoomRegistry.close(fetch_room_id())
              {%{state | public: false}, [{:broadcast_public_status, false}]}
            else
              :ok = LimbusRealtime.Realtime.PublicRoomRegistry.update(fetch_room_id(), players)
              {state, []}
            end

          {:ok, state,
           [{:send_state, participant.id}, {:broadcast_joined, participant.display_name}] ++
             effect}
      end
    end
  end

  defp assign_host(%State{host_client_id: nil} = state, client_id, mode, initial_settings) do
    %{
      state
      | host_client_id: client_id,
        mode:
          case mode do
            "battleRoyale" -> :battle_royale
            _ -> :standard
          end,
        settings: initial_settings || %{}
    }
  end

  defp assign_host(state, _, _, _), do: state

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

  def open_to_public(payload, _connection, state) do
    with :ok <- check_host(payload, state),
         :ok <- check_phase(:setup, state),
         true <- map_size(state.participants) < @max_players[state.mode],
         room_id <- fetch_room_id() do
      :ok =
        LimbusRealtime.Realtime.PublicRoomRegistry.open(
          room_id,
          public_room_type(state),
          state.participants[state.host_client_id].display_name,
          map_size(state.participants),
          @max_players[state.mode]
        )

      {:ok, %{state | public: true}, [{:broadcast_public_status, true}]}
    else
      false -> {:error, "room_full"}
      {:error, reason} -> {:error, reason}
    end
  end

  def close_to_public(payload, _connection, state) do
    with :ok <- check_host(payload, state),
         :ok <- check_phase(:setup, state),
         room_id <- fetch_room_id() do
      :ok = LimbusRealtime.Realtime.PublicRoomRegistry.close(room_id)

      {:ok, %{state | public: false}, [{:broadcast_public_status, false}]}
    end
  end

  def start_draft(payload, _connection, state) do
    with :ok <- check_host(payload, state),
         :ok <- check_phase(:setup, state) do
      :ok = LimbusRealtime.Realtime.PublicRoomRegistry.close(fetch_room_id())

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
        if state.mode == :battle_royale do
          List.duplicate(:identity, state.settings["team_size"]) ++
            if state.settings["ego_draft"], do: [:ego], else: []
        else
          build_draft_order(
            player_ids,
            state.settings["team_size"],
            state.settings["draft_order"],
            state.settings["ego_draft"],
            state.settings["blacklisting"]
          )
        end

      state =
        %{
          state
          | phase: :draft,
            public: false,
            participants: participants,
            draft_order: draft_order,
            draft_index: 0,
            picked_identities: MapSet.new(),
            picked_egos: MapSet.new(),
            item_data: %{},
            blacklisted_identities: MapSet.new()
        }
        |> add_draft_points(0)

      {:ok, state, [:broadcast_draft_started]}
    else
      {:error, reason} ->
        {:error, reason}
    end
  end

  def pick_item(payload, _connection, state) do
    case Enum.at(state.draft_order, state.draft_index) do
      :blacklist ->
        vote_blacklist(payload, state)

      _ ->
        pick_draft_item(payload, state)
    end
  end

  defp vote_blacklist(payload, state) do
    client_id = payload.user.client_id
    item_id = payload["item_id"]

    with :ok <- check_phase(:draft, state),
         :ok <- check_participant(payload, state),
         false <- Map.has_key?(state.blacklist_votes, client_id),
         true <- check_identity_blacklist(item_id) do
      votes = Map.put(state.blacklist_votes, client_id, item_id)
      state = %{state | blacklist_votes: votes}

      if map_size(votes) == map_size(state.participants) do
        resolve_blacklist(state)
      else
        {:ok, state, [:broadcast_blacklist_state]}
      end
    else
      true ->
        {:error, "already_voted"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp check_identity_blacklist(identity_id) do
    cond do
      identity_id == nil ->
        true

      not is_binary(identity_id) ->
        {:error, "invalid_identity"}

      not ClashingData.has_id?(identity_id) ->
        {:error, "invalid_identity"}

      true ->
        true
    end
  end

  defp resolve_blacklist(state) do
    newly_blacklisted =
      state.blacklist_votes
      |> Map.values()
      |> Enum.reject(fn
        nil -> true
        identity_id -> MapSet.member?(state.picked_identities, identity_id)
      end)
      |> MapSet.new()

    blacklisted_identities =
      MapSet.union(state.blacklisted_identities, newly_blacklisted)

    draft_index = state.draft_index + 1

    state = %{
      state
      | blacklisted_identities: blacklisted_identities,
        blacklist_votes: %{},
        draft_index: draft_index
    }

    state = state |> add_draft_points(draft_index)
    {:ok, state, [{:broadcast_blacklist_resolved, draft_index}]}
  end

  defp pick_draft_item(payload, state) do
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
                picked_identities: MapSet.put(state.picked_identities, item_id)
            }

          :ego ->
            %{
              state
              | participants: participants,
                picked_egos: MapSet.put(state.picked_egos, item_id)
            }
        end

      if state.mode == :battle_royale do
        submitted_count =
          Enum.count(state.participants, fn {_id, p} ->
            case Enum.at(state.draft_order, draft_index) do
              :identity -> length(p.identities) > draft_index
              :ego -> not is_nil(p.ego)
            end
          end)

        if submitted_count == map_size(state.participants) do
          state = %{state | draft_index: draft_index + 1}

          if state.draft_index >= length(state.draft_order) do
            {:ok, finish_draft(state), [:broadcast_state]}
          else
            state = add_draft_points(state, state.draft_index)

            {:ok, state, [{:broadcast_draft_round_complete, draft_index}]}
          end
        else
          effects = [{:send_draft_successful, type, item_id}]

          effects =
            if rem(submitted_count, 10) == 0 do
              [{:send_draft_progress, submitted_count} | effects]
            else
              effects
            end

          {:ok, state, effects}
        end
      else
        state = %{state | draft_index: draft_index + 1}

        if state.draft_index >= length(state.draft_order) do
          {:ok, finish_draft(state), [:broadcast_state]}
        else
          state = add_draft_points(state, state.draft_index)
          {:ok, state, [{:broadcast_draft_pick, type, item_id, draft_index}]}
        end
      end
    else
      {:error, reason} ->
        {:error, reason}
    end
  end

  def force_advance_draft(payload, _connection, state) do
    with :ok <- check_phase(:draft, state),
         :ok <- check_host(payload, state),
         :ok <- check_battle_royale(state) do
      draft_index = state.draft_index
      draft_type = Enum.at(state.draft_order, draft_index)

      participants =
        Map.new(state.participants, fn {client_id, participant} ->
          participant =
            case draft_type do
              :identity when length(participant.identities) == draft_index ->
                %{participant | identities: participant.identities ++ [nil]}

              _ ->
                participant
            end

          {client_id, participant}
        end)

      state = %{state | participants: participants, draft_index: draft_index + 1}

      state =
        if draft_index + 1 >= length(state.draft_order) do
          finish_draft(state)
        else
          add_draft_points(state, draft_index + 1)
        end

      effects =
        if state.phase == :draft_complete do
          [:broadcast_state]
        else
          [{:broadcast_draft_round_complete, draft_index}]
        end

      {:ok, state, effects}
    else
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp check_battle_royale(%State{mode: :battle_royale}), do: :ok
  defp check_battle_royale(_state), do: {:error, "invalid_mode"}

  defp add_draft_points(state, draft_index) do
    points = state.settings["points_per_draft"]

    cond do
      points <= 0 ->
        state

      state.mode == :battle_royale ->
        draft_type = Enum.at(state.draft_order, draft_index)

        to_add =
          case draft_type do
            :identity -> points
            :ego -> ceil(points / 2) |> trunc()
            _ -> 0
          end

        update_in(state.participants, fn participants ->
          Map.new(participants, fn {id, participant} ->
            {id, %{participant | draft_points: participant.draft_points + to_add}}
          end)
        end)

      Enum.at(state.draft_order, draft_index) != :blacklist ->
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

      true ->
        state
    end
  end

  defp finish_draft(state) do
    selected_ids =
      state.picked_identities
      |> MapSet.union(state.picked_egos)
      |> MapSet.to_list()

    participants =
      Map.new(state.participants, fn {client_id, participant} ->
        identities = Enum.reject(participant.identities, &is_nil/1)

        skill_counts = Map.new(identities, fn identity_id ->
            {identity_id, [3, 2, 1, 0]}
          end)

        {client_id, %{participant | identities: identities, skill_counts: skill_counts, ego_used: false, score: 0}}
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

  def start_game(payload, _connection, state) do
    with :ok <- check_host(payload, state),
         :ok <- check_phase(:draft_complete, state) do
      state = %{
        state
        | phase: :round_select,
          round_number: 1,
          submissions: %{},
          results: %{},
          blacklisted_identities: MapSet.new()
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
      submitted_count = map_size(state.submissions)

      effects = [{:broadcast_skill_chosen, type, item_id, skill}]

      if submitted_count == map_size(state.participants) do
        {:ok, resolve_round(state), [:broadcast_round_reveal | effects]}
      else
        if state.mode == :battle_royale do
          if rem(submitted_count, 10) == 0 do
            {:ok, state, [{:send_round_progress, submitted_count} | effects]}
          else
            {:ok, state, effects}
          end
        else
          {:ok, state, effects}
        end
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

  def force_advance_round(payload, _connection, state) do
    with :ok <- check_host(payload, state),
         :ok <- check_phase(:round_select, state),
         true <- map_size(state.submissions) > 0 do
      {:ok, resolve_round(state), [:broadcast_round_reveal]}
    else
      false -> {:error, "no_submissions"}
      {:error, reason} -> {:error, reason}
    end
  end

  defp resolve_round(state) do
    teams =
      Map.new(state.participants, fn {client_id, participant} ->
        {client_id, {participant.identities, participant.ego}}
      end)

    results =
      Simulator.simulate_round(
        state.current_round,
        state.submissions,
        state.item_data,
        teams
      )
      |> distribute_points(state)

    participants =
      Map.new(state.participants, fn {client_id, participant} ->
        case Map.get(results, client_id) do
          %{points: points} ->
            {client_id, %{participant | score: participant.score + points}}

          _ ->
            {client_id, participant}
        end
      end)

    results =
      Map.new(results, fn {client_id, result} ->
        {state.participants[client_id].player_id, Map.merge(result, state.submissions[client_id])}
      end)

    %{state | phase: :round_reveal, participants: participants, results: results}
  end

  defp distribute_points(results, %{mode: :standard}) do
    highest = results |> Map.values() |> Enum.map(& &1.clash_value) |> Enum.max()

    Map.new(results, fn {client_id, result} ->
      {client_id, Map.put(result, :points, if(result.clash_value == highest, do: 1, else: 0))}
    end)
  end

  defp distribute_points(results, %{mode: :battle_royale, settings: %{"scoring" => "value"}}) do
    Map.new(results, fn {client_id, result} ->
      {client_id, Map.put(result, :points, result.clash_value)}
    end)
  end

  defp distribute_points(results, state = %{mode: :battle_royale}) do
    results
    |> Enum.group_by(fn {_client_id, result} -> result.clash_value end)
    |> Enum.sort_by(fn {clash_value, _players} -> clash_value end, :desc)
    |> Enum.reduce({%{}, 1}, fn {_clash_value, players}, {scored, rank} ->
      points = map_size(state.participants) - rank + 1

      scored =
        Enum.reduce(players, scored, fn {client_id, result}, acc ->
          Map.put(acc, client_id, Map.put(result, :points, points))
        end)

      {scored, rank + length(players)}
    end)
    |> elem(0)
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

              players = map_size(participants)

              {state, effect} =
                if players == 0 do
                  :ok = LimbusRealtime.Realtime.PublicRoomRegistry.close(fetch_room_id())
                  {%{state | public: false}, [{:broadcast_public_status, false}]}
                else
                  :ok =
                    LimbusRealtime.Realtime.PublicRoomRegistry.update(fetch_room_id(), players)

                  {state, []}
                end

              {state, [{:broadcast_left, participant.display_name}] ++ effect}
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

  defp build_draft_order(player_ids, team_size, mode, ego_draft, blacklisting) do
    identity_order =
      case mode do
        "snake" ->
          build_snake_draft_order(player_ids, team_size)

        "random" ->
          build_random_draft_order(player_ids, team_size)

        _ ->
          build_cycle_draft_order(player_ids, team_size)
      end

    identity_order =
      if blacklisting do
        identity_order
        |> Enum.chunk_every(length(player_ids) * 2)
        |> Enum.intersperse([:blacklist])
        |> List.flatten()
      else
        identity_order
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
    case {state.mode, Enum.at(state.draft_order, state.draft_index)} do
      {:battle_royale, :identity} ->
        check_identity(item_id, client_id, state)

      {:battle_royale, :ego} ->
        check_ego(item_id, client_id, state)

      {_, "e-" <> _} ->
        check_ego(item_id, client_id, state)

      _ ->
        check_identity(item_id, client_id, state)
    end
  end

  defp check_identity(identity_id, client_id, state) do
    cond do
      not is_binary(identity_id) ->
        {:error, "invalid_identity"}

      state.mode != :battle_royale and
          MapSet.member?(state.picked_identities, identity_id) ->
        {:error, "identity_already_picked"}

      state.mode == :battle_royale and
          Enum.member?(state.participants[client_id].identities, identity_id) ->
        {:error, "identity_already_picked"}

      MapSet.member?(state.blacklisted_identities, identity_id) ->
        {:error, "identity_blacklisted"}

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
          {:ok, :id, 0}
        end
    end
  end

  defp check_ego(ego_id, client_id, state) do
    cond do
      not is_binary(ego_id) ->
        {:error, "invalid_ego"}

      state.mode != :battle_royale and
          MapSet.member?(state.picked_egos, ego_id) ->
        {:error, "ego_already_picked"}

      state.mode == :battle_royale and
          state.participants[client_id].ego == ego_id ->
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
          {:ok, :ego, 0}
        end
    end
  end

  defp check_draft_turn(payload, state) do
    if state.mode == :battle_royale do
      participant = state.participants[payload.user.client_id]

      already_submitted =
        case Enum.at(state.draft_order, state.draft_index) do
          :identity -> length(participant.identities) > state.draft_index
          :ego -> not is_nil(participant.ego)
        end

      if already_submitted, do: {:error, "already_submitted"}, else: :ok
    else
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

  defp fetch_room_id do
    case Registry.keys(LimbusRealtime.RoomRegistry, self()) do
      [room_id] -> room_id
      _ -> nil
    end
  end

  defp public_room_type(state) do
    case state.mode do
      :standard -> :clash_battle
      :battle_royale -> :clash_battle_royale
    end
  end
end
