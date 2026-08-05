defmodule LimbusRealtime.Realtime.Connection do
  @enforce_keys [:id]

  defstruct [
    :id,
    :joined_at
  ]

  @type t :: %__MODULE__{
          id: String.t(),
          joined_at: DateTime.t()
        }
end
