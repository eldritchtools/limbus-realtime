defmodule LimbusRealtime.Realtime.Components.ClashBattle.State do
  defstruct phase: :setup,
            host_client_id: nil,
            participants: %{},
            player_order: [],
            settings: %{},
            draft_order: [],
            draft_index: 0,
            picked_identities: MapSet.new(),
            identity_data: %{},
            submissions: %{},
            current_round: nil,
            round_number: 0,
            results: %{}

  @type phase :: :setup | :draft | :draft_complete | :round_select | :round_reveal | :finished

  @type participant :: %{
          id: String.t(),
          player_id: non_neg_integer() | nil,
          display_name: String.t(),
          score: non_neg_integer(),
          connected: boolean(),
          channel_pid: pid(),
          identities: [String.t()],
          skill_counts: %{String.t() => [non_neg_integer()]} | nil
        }

  @type t :: %__MODULE__{
          phase: phase(),
          host_client_id: String.t() | nil,
          participants: %{String.t() => participant()},
          player_order: [String.t()],
          settings: %{String.t() => any()},
          draft_order: [non_neg_integer()],
          draft_index: non_neg_integer(),
          picked_identities: MapSet.t(),
          identity_data: %{String.t() => map()},
          submissions: %{String.t() => any()},
          current_round: map() | nil,
          round_number: non_neg_integer(),
          results: %{String.t() => any()}
        }
end
