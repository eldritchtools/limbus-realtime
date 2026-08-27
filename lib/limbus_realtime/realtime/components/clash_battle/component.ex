defmodule LimbusRealtime.Realtime.Components.ClashBattle.Component do
  alias LimbusRealtime.Realtime.Components.ClashBattle.State
  alias LimbusRealtime.Realtime.Components.ClashBattle.Generator
  alias LimbusRealtime.Realtime.Components.ClashBattle.Simulator
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
            channel_pid: user.channel_pid
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
          {client_id, %{participant | player_id: player_id, identities: [], score: 0}}
        end)

      player_ids =
        state.player_order
        |> Enum.map(&participants[&1].player_id)

      draft_order =
        build_draft_order(
          player_ids,
          state.settings["team_size"],
          state.settings["draft_order"]
        )

      state = %{
        state
        | phase: :draft,
          participants: participants,
          draft_order: draft_order,
          draft_index: 0,
          picked_identities: MapSet.new(),
          identity_data: %{}
      }

      {:ok, state, [:broadcast_draft_started]}
    else
      {:error, reason} ->
        {:error, reason}
    end
  end

  def pick_identity(payload, _connection, state) do
    with :ok <- check_phase(:draft, state),
         :ok <- check_draft_turn(payload, state),
         :ok <- check_identity(payload["identity_id"], state) do
      client_id = payload.user.client_id
      identity_id = payload["identity_id"]
      draft_index = state.draft_index

      participant = Map.fetch!(state.participants, client_id)

      participants =
        put_in(
          state.participants,
          [client_id, :identities],
          participant.identities ++ [identity_id]
        )

      state = %{
        state
        | participants: participants,
          picked_identities: MapSet.put(state.picked_identities, identity_id),
          draft_index: draft_index + 1
      }

      if state.draft_index >= length(state.draft_order) do
        state = finish_draft(state)

        {:ok, state, [:broadcast_draft_complete]}
      else
        {:ok, state, [{:broadcast_draft_pick, identity_id, draft_index}]}
      end
    else
      {:error, reason} ->
        {:error, reason}
    end
  end

  def start_game(payload, _connection, state) do
    with :ok <- check_host(payload, state),
         :ok <- check_phase(:draft_complete, state) do
      participants =
        Map.new(state.participants, fn {client_id, participant} ->
          skill_counts =
            Map.new(participant.identities, fn identity_id ->
              {identity_id, [3, 2, 1]}
            end)

          {client_id, %{participant | skill_counts: skill_counts, score: 0}}
        end)

      state = %{
        state
        | phase: :round_select,
          participants: participants,
          round_number: 1,
          current_round: Generator.generate_round(state.settings),
          submissions: %{},
          results: %{}
      }

      {:ok, state, [:broadcast_round]}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  def select_skill(payload, _connection, state) do
    client_id = payload.user.client_id
    identity_id = payload["identity_id"]
    skill = payload["skill"]

    with :ok <- check_phase(:round_select, state),
         :ok <- check_participant(payload, state),
         false <- Map.has_key?(state.submissions, client_id),
         {:ok, participant} <-
           consume_skill(state.participants[client_id], identity_id, skill) do
      submission = %{
        identity_id: identity_id,
        skill: skill
      }

      state = put_in(state.participants[client_id], participant)
      state = put_in(state.submissions[client_id], submission)

      if map_size(state.submissions) == map_size(state.participants) do
        {:ok, resolve_round(state),
         [{:broadcast_skill_chosen, identity_id, skill}, :broadcast_round_reveal]}
      else
        {:ok, state, [{:broadcast_skill_chosen, identity_id, skill}]}
      end
    else
      true ->
        {:error, "already_submitted"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp consume_skill(participant, identity_id, skill) do
    case participant.skill_counts[identity_id] do
      nil ->
        {:error, "invalid_identity"}

      counts ->
        index = skill - 1

        if Enum.at(counts, index, 0) > 0 do
          counts = List.update_at(counts, index, &(&1 - 1))

          participant = %{
            participant
            | skill_counts: Map.put(participant.skill_counts, identity_id, counts)
          }

          {:ok, participant}
        else
          {:error, "skill_unavailable"}
        end
    end
  end

  defp resolve_round(state) do
    results =
      Simulator.simulate_round(
        state.current_round,
        state.submissions,
        state.identity_data
      )

    participants =
      Map.new(state.participants, fn {client_id, participant} ->
        {client_id, %{participant | score: participant.score + results[client_id].points}}
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
            current_round: Generator.generate_round(state.settings),
            submissions: %{},
            results: %{},
            round_number: state.round_number + 1
        }

        {:ok, state, [:broadcast_round]}
      end
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
      state.participants
      |> Map.values()
      |> Enum.flat_map(& &1.identities)

    %{
      state
      | phase: :draft_complete,
        draft_order: [],
        draft_index: 0,
        round_number: 0,
        identity_data: ClashingData.get(selected_ids),
        submissions: %{},
        current_round: nil
    }
  end

  defp build_draft_order(player_ids, team_size, mode) do
    case mode do
      "snake" ->
        build_snake_draft_order(player_ids, team_size)

      "random" ->
        build_random_draft_order(player_ids, team_size)

      _ ->
        build_cycle_draft_order(player_ids, team_size)
    end
  end

  defp build_cycle_draft_order(player_ids, team_size) do
    List.duplicate(player_ids, team_size)
    |> List.flatten()
  end

  defp build_snake_draft_order(player_ids, team_size) do
    player_ids
    |> List.duplicate(team_size)
    |> Enum.with_index()
    |> Enum.map(fn {ids, index} ->
      if rem(index, 2) == 0 do
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

  defp check_identity(identity_id, state) do
    cond do
      not is_binary(identity_id) ->
        {:error, "invalid_identity"}

      MapSet.member?(state.picked_identities, identity_id) ->
        {:error, "identity_already_picked"}

      not ClashingData.has_id?(identity_id) ->
        {:error, "invalid_identity"}

      true ->
        :ok
    end
  end

  defp check_draft_turn(payload, state) do
    current_client_id =
      state.draft_order
      |> Enum.at(state.draft_index)
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
