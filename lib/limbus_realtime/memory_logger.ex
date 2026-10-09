defmodule LimbusRealtime.MemoryLogger do
  use GenServer

  require Logger

  @interval :timer.minutes(5)

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  end

  @impl true
  def init(_) do
    schedule_log()
    {:ok, nil}
  end

  @impl true
  def handle_info(:log_memory, state) do
    memory = :erlang.memory()

    Logger.info(
      "VM memory: total=#{Float.round(memory[:total] / 1_048_576, 1)} MB " <>
        "processes=#{Float.round(memory[:processes] / 1_048_576, 1)} MB " <>
        "binary=#{Float.round(memory[:binary] / 1_048_576, 1)} MB"
    )

    schedule_log()
    {:noreply, state}
  end

  defp schedule_log do
    Process.send_after(self(), :log_memory, @interval)
  end
end
