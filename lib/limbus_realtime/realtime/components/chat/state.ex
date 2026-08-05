defmodule LimbusRealtime.Realtime.Components.Chat.State do
  @history_limit 50
  @history_window_minutes 30

  defstruct history: [],
            participants: %{},
            connections: %{}

  @type message :: %{
          id: String.t(),
          connection_id: String.t(),
          text: String.t(),
          sent_at: DateTime.t()
        }

  @type participant :: %{
          id: String.t(),
          display_name: String.t(),
          connection_count: integer()
        }

  @type connection :: %{
          participant_id: String.t()
        }

  @type t :: %__MODULE__{
          history: [message()],
          participants: %{String.t() => participant()},
          connections: %{String.t() => connection()}
        }

  def history_limit, do: @history_limit
  def history_window_minutes, do: @history_window_minutes
end
