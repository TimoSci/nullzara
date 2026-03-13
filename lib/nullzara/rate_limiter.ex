defmodule Nullzara.RateLimiter do
  @moduledoc """
  ETS-based per-IP rate limiter with namespaced buckets.

  Each bucket (e.g., :verify, :create) can have its own max attempts
  and time window, configured per environment in config files.
  """

  use GenServer

  @table __MODULE__

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def record(bucket, ip) do
    now = System.monotonic_time(:millisecond)
    :ets.insert(@table, {{bucket, ip}, now})
  end

  def blocked?(bucket, ip) do
    {max, window_ms} = limit_for(bucket)
    cutoff = System.monotonic_time(:millisecond) - window_ms
    key = {bucket, ip}
    hits = :ets.select(@table, [{{key, :"$1"}, [{:>=, :"$1", cutoff}], [true]}])
    length(hits) >= max
  end

  def clear(bucket, ip) do
    :ets.match_delete(@table, {{bucket, ip}, :_})
  end

  defp limit_for(bucket) do
    limits = Application.get_env(:nullzara, __MODULE__, []) |> Keyword.get(:limits, %{})
    Map.get(limits, bucket, {10, :timer.minutes(10)})
  end

  defp cleanup_interval do
    Application.get_env(:nullzara, __MODULE__, [])
    |> Keyword.get(:cleanup_interval_ms, :timer.minutes(1))
  end

  # Callbacks

  @impl true
  def init(_opts) do
    :ets.new(@table, [:named_table, :duplicate_bag, :public])
    schedule_cleanup()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:cleanup, state) do
    limits = Application.get_env(:nullzara, __MODULE__, []) |> Keyword.get(:limits, %{})

    max_window =
      limits
      |> Map.values()
      |> Enum.map(fn {_max, window} -> window end)
      |> Enum.max(fn -> :timer.minutes(10) end)

    cutoff = System.monotonic_time(:millisecond) - max_window
    :ets.select_delete(@table, [{{:_, :"$1"}, [{:<, :"$1", cutoff}], [true]}])
    schedule_cleanup()
    {:noreply, state}
  end

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup, cleanup_interval())
  end
end
