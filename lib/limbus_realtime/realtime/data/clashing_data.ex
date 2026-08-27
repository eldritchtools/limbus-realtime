defmodule LimbusRealtime.Realtime.Data.ClashingData do
  use GenServer

  @refresh_interval :timer.hours(24)

  # Public API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def has_id?(id) do
    GenServer.call(__MODULE__, {:has_id, id})
  end

  def get(ids) when is_list(ids) do
    GenServer.call(__MODULE__, {:get, ids})
  end

  def refresh do
    GenServer.cast(__MODULE__, :refresh)
  end

  # GenServer callbacks

  @impl true
  def init(_opts) do
    state =
      case fetch_data() do
        {:ok, data} ->
          data

        {:error, reason} ->
          IO.warn("Failed to load skill data: #{inspect(reason)}")
          %{}
      end

    schedule_refresh()

    {:ok, state}
  end

  @impl true
  def handle_call({:has_id, id}, _from, data) do
    if Map.has_key?(data, id) do
      {:reply, true, data}
    else
      case fetch_data() do
        {:ok, new_data} ->
          {:reply, Map.has_key?(new_data, id), new_data}

        {:error, reason} ->
          IO.warn("Failed to refresh skill data: #{inspect(reason)}")
          {:reply, false, data}
      end
    end
  end

  @impl true
  def handle_call({:get, ids}, _from, data) do
    {:reply, Map.take(data, ids), data}
  end

  @impl true
  def handle_cast(:refresh, data) do
    case fetch_data() do
      {:ok, new_data} ->
        {:noreply, new_data}

      {:error, reason} ->
        IO.warn("Failed to refresh skill data: #{inspect(reason)}")
        {:noreply, data}
    end
  end

  @impl true
  def handle_info(:refresh, data) do
    schedule_refresh()

    case fetch_data() do
      {:ok, new_data} ->
        {:noreply, new_data}

      {:error, reason} ->
        IO.warn("Failed to refresh skill data: #{inspect(reason)}")
        {:noreply, data}
    end
  end

  # Helpers

  defp schedule_refresh do
    Process.send_after(self(), :refresh, @refresh_interval)
  end

  defp fetch_data do
    url = "https://limbus-assets.eldritchtools.com/data/clashing_data.json"

    case Req.get(url) do
      {:ok, %{status: 200, body: body}} when is_map(body) ->
        {:ok, body}

      {:ok, %{status: status}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
