defmodule Nullzara.RateLimiterTest do
  use ExUnit.Case, async: false

  alias Nullzara.RateLimiter

  setup do
    RateLimiter.clear(:verify, "test_ip")
    RateLimiter.clear(:create, "test_ip")
    RateLimiter.clear(:verify, "blocked_ip")
    RateLimiter.clear(:verify, "other_ip")
    :ok
  end

  describe "record/2 and blocked?/2" do
    test "is not blocked below threshold" do
      for _ <- 1..9, do: RateLimiter.record(:verify, "test_ip")
      refute RateLimiter.blocked?(:verify, "test_ip")
    end

    test "is blocked after reaching threshold" do
      for _ <- 1..10, do: RateLimiter.record(:verify, "test_ip")
      assert RateLimiter.blocked?(:verify, "test_ip")
    end

    test "different IPs are tracked independently" do
      for _ <- 1..10, do: RateLimiter.record(:verify, "blocked_ip")
      refute RateLimiter.blocked?(:verify, "other_ip")
    end

    test "different buckets are tracked independently" do
      for _ <- 1..10, do: RateLimiter.record(:verify, "test_ip")
      assert RateLimiter.blocked?(:verify, "test_ip")
      refute RateLimiter.blocked?(:create, "test_ip")
    end
  end

  describe "clear/2" do
    test "unblocks an IP for a specific bucket" do
      for _ <- 1..10, do: RateLimiter.record(:verify, "test_ip")
      assert RateLimiter.blocked?(:verify, "test_ip")

      RateLimiter.clear(:verify, "test_ip")
      refute RateLimiter.blocked?(:verify, "test_ip")
    end
  end
end
