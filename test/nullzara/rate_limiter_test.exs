defmodule Nullzara.RateLimiterTest do
  use ExUnit.Case, async: false

  alias Nullzara.RateLimiter

  setup do
    # RateLimiter is started by the application, clear state between tests
    RateLimiter.clear("test_ip")
    :ok
  end

  describe "record_failure/1 and blocked?/1" do
    test "is not blocked with fewer than 10 failures" do
      for _ <- 1..9, do: RateLimiter.record_failure("test_ip")
      refute RateLimiter.blocked?("test_ip")
    end

    test "is blocked after 10 failures" do
      for _ <- 1..10, do: RateLimiter.record_failure("test_ip")
      assert RateLimiter.blocked?("test_ip")
    end

    test "different IPs are tracked independently" do
      for _ <- 1..10, do: RateLimiter.record_failure("blocked_ip")
      refute RateLimiter.blocked?("other_ip")
    end
  end

  describe "clear/1" do
    test "unblocks an IP" do
      for _ <- 1..10, do: RateLimiter.record_failure("test_ip")
      assert RateLimiter.blocked?("test_ip")

      RateLimiter.clear("test_ip")
      refute RateLimiter.blocked?("test_ip")
    end
  end
end
