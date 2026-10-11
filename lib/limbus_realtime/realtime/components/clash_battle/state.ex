defmodule LimbusRealtime.Realtime.Components.ClashBattle.State do
  defstruct mode: :standard,
            phase: :setup,
            host_client_id: nil,
            public: false,
            participants: %{},
            player_order: [],
            settings: %{},
            draft_order: [],
            draft_index: 0,
            picked_identities: MapSet.new(),
            picked_egos: MapSet.new(),
            item_data: %{},
            submissions: %{},
            current_round: nil,
            round_number: 0,
            results: %{},
            blacklist_votes: %{},
            blacklisted_identities: MapSet.new()

  @type mode :: :standard | :battle_royale
  @type phase :: :setup | :draft | :draft_complete | :round_select | :round_reveal | :finished

  @type participant :: %{
          id: String.t(),
          player_id: non_neg_integer() | nil,
          display_name: String.t(),
          score: non_neg_integer(),
          connected: boolean(),
          channel_pid: pid(),
          identities: [String.t() | nil],
          skill_counts: %{String.t() => [non_neg_integer()]} | nil,
          draft_points: non_neg_integer(),
          ego: String.t() | nil,
          ego_used: boolean()
        }

  @type t :: %__MODULE__{
          mode: mode(),
          phase: phase(),
          host_client_id: String.t() | nil,
          public: boolean(),
          participants: %{String.t() => participant()},
          player_order: [String.t()],
          settings: %{String.t() => any()},
          draft_order: [any()],
          draft_index: non_neg_integer(),
          picked_identities: MapSet.t(),
          picked_egos: MapSet.t(),
          item_data: %{String.t() => map()},
          submissions: %{String.t() => any()},
          current_round: map() | nil,
          round_number: non_neg_integer(),
          results: %{String.t() => any()},
          blacklist_votes: %{String.t() => String.t()},
          blacklisted_identities: MapSet.t()
        }
end
