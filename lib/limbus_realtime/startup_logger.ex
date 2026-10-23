defmodule LimbusRealtime.StartupLogger do
  use GenServer

  require Logger

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  def init(state) do
    Logger.warning("Application process started at #{DateTime.utc_now()}")
    {:ok, state}
  end
end
