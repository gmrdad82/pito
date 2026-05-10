require "rails_helper"

RSpec.describe Igdb::RateLimiter do
  describe "#acquire" do
    it "allows up to `rate` requests within `interval` immediately" do
      limiter = described_class.new(rate: 4, interval: 1.0, concurrency: 8)
      timings = []
      start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      4.times do
        limiter.acquire { timings << Process.clock_gettime(Process::CLOCK_MONOTONIC) - start }
      end
      expect(timings.last).to be < 0.1
    end

    it "blocks the (rate+1)th call until the window rolls" do
      limiter = described_class.new(rate: 2, interval: 0.5, concurrency: 8)
      4.times { limiter.acquire { :ok } }
      start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      limiter.acquire { :ok }
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
      expect(elapsed).to be >= 0.4
    end

    it "allows up to `concurrency` in flight; blocks the (concurrency+1)th" do
      limiter = described_class.new(rate: 100, interval: 1.0, concurrency: 2)
      released = []
      threads = 3.times.map do |i|
        Thread.new do
          limiter.acquire { sleep 0.2; released << i }
        end
      end
      threads.each(&:join)
      expect(released.size).to eq(3)
    end

    it "returns the block's value" do
      limiter = described_class.new(rate: 4, interval: 1.0, concurrency: 8)
      expect(limiter.acquire { 42 }).to eq(42)
    end

    it "releases the slot when the block raises" do
      limiter = described_class.new(rate: 100, interval: 1.0, concurrency: 1)
      expect {
        limiter.acquire { raise "boom" }
      }.to raise_error("boom")
      # second acquire must succeed quickly
      start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      limiter.acquire { :ok }
      expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - start).to be < 0.1
    end
  end

  describe ".shared" do
    it "returns the same instance across calls" do
      described_class.reset_shared!
      a = described_class.shared
      b = described_class.shared
      expect(a).to be(b)
    end
  end
end
