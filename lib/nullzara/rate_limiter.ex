defmodule Nullzara.RateLimiter do
  @moduledoc """
  ETS-based per-IP failure counter to guard against brute-force attacks.
  Blocks an IP after 10 failures within a 10-minute window.
  """

  use GenServer

  @table __MODULE__
  @max_failures 10
  @window_ms :timer.minutes(10)
  @cleanup_interval_ms :timer.minutes(1)

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def record_failure(ip) do
    now = System.monotonic_time(:millisecond)
    :ets.insert(@table, {ip, now})
  end

  def blocked?(ip) do
    cutoff = System.monotonic_time(:millisecond) - @window_ms
    failures = :ets.select(@table, [{{ip, :"$1"}, [{:>=, :"$1", cutoff}], [true]}])
    length(failures) >= @max_failures
  end

  def clear(ip) do
    :ets.delete(@table, ip)
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
    cutoff = System.monotonic_time(:millisecond) - @window_ms
    :ets.select_delete(@table, [{{:_, :"$1"}, [{:<, :"$1", cutoff}], [true]}])
    schedule_cleanup()
    {:noreply, state}
  end

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup, @cleanup_interval_ms)
  end
end
