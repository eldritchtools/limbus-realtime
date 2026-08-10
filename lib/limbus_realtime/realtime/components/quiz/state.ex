defmodule LimbusRealtime.Realtime.Components.Quiz.State do
  defstruct phase: :setup,
            host_client_id: nil,
            participants: %{},
            current_question: nil,
            current_answer: nil,
            question_number: 0,
            submissions: %{},
            settings: %{}

  @type phase :: :setup | :question | :reveal | :finished

  @type participant :: %{
          id: String.t(),
          display_name: String.t(),
          score: non_neg_integer(),
          connected: boolean(),
          channel_pid: pid()
        }

  @type t :: %__MODULE__{
          phase: phase(),
          host_client_id: String.t() | nil,
          participants: %{String.t() => participant()},
          current_question: map() | nil,
          current_answer: any(),
          question_number: non_neg_integer(),
          submissions: %{String.t() => any()},
          settings: %{String.t() => any()}
        }
end
