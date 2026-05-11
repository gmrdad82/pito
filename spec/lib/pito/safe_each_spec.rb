require "rails_helper"

# 2026-05-11 — iterate-and-soft-fail wrapper. Replaces the duplicated
# `begin / rescue StandardError / Rails.logger.warn / next` scaffolding
# the reviewer flagged in `Calendar::MilestoneEvaluator` (and adjacent
# sweep services). See `app/lib/pito/safe_each.rb`.
RSpec.describe Pito::SafeEach do
  describe ".call" do
    let(:logger) { instance_double(ActiveSupport::Logger, warn: nil) }

    it "yields every element in order on the happy path" do
      seen = []
      described_class.call([ :a, :b, :c ], label: "T", logger: logger) { |x| seen << x }
      expect(seen).to eq([ :a, :b, :c ])
    end

    it "returns the input collection so callers can chain" do
      rows = [ 1, 2, 3 ]
      out = described_class.call(rows, label: "T", logger: logger) { |_| }
      expect(out).to be(rows)
    end

    it "raises ArgumentError when called without a block" do
      expect {
        described_class.call([ 1 ], label: "T", logger: logger)
      }.to raise_error(ArgumentError, /requires a block/)
    end

    it "swallows StandardError from a single element and continues iteration" do
      seen = []
      described_class.call([ 1, 2, 3 ], label: "T", logger: logger) do |n|
        raise "boom on 2" if n == 2

        seen << n
      end
      expect(seen).to eq([ 1, 3 ])
    end

    it "logs a warn line that includes the label, error class, and message" do
      described_class.call([ :only ], label: "Sweeper", logger: logger) do |_|
        raise ArgumentError, "the message"
      end
      expect(logger).to have_received(:warn).with(
        a_string_matching(/\[Sweeper\].*ArgumentError.*the message/)
      )
    end

    it "logs the row identifier (`id`) for AR-like rows" do
      row = double("row", id: 42, inspect: "<row#42>")
      described_class.call([ row ], label: "T", logger: logger) do |_|
        raise "boom"
      end
      expect(logger).to have_received(:warn).with(a_string_matching(/row=42/))
    end

    it "falls back to a truncated inspect when the row has no usable id" do
      row = double("row", id: nil, inspect: "X" * 200)
      described_class.call([ row ], label: "T", logger: logger) do |_|
        raise "boom"
      end
      expect(logger).to have_received(:warn).with(a_string_matching(/row=X{80}\)/))
    end

    it "does NOT swallow non-StandardError descendants (SystemExit bubbles)" do
      expect {
        described_class.call([ 1 ], label: "T", logger: logger) do |_|
          raise SystemExit
        end
      }.to raise_error(SystemExit)
    end

    it "handles an empty collection without invoking the block or warn" do
      seen = false
      described_class.call([], label: "T", logger: logger) { |_| seen = true }
      expect(seen).to be(false)
      expect(logger).not_to have_received(:warn)
    end

    it "works with an Enumerator (e.g. `find_each` without a block)" do
      seen = []
      enum = [ :x, :y ].each
      described_class.call(enum, label: "T", logger: logger) { |v| seen << v }
      expect(seen).to eq([ :x, :y ])
    end

    it "dispatches via `with_iterator:` so AR callers can use `find_each`" do
      rows = double("rows")
      block_called_with = []
      allow(rows).to receive(:find_each).and_yield(:a).and_yield(:b)

      described_class.call(rows, label: "T", logger: logger, with_iterator: :find_each) do |row|
        block_called_with << row
      end
      expect(rows).to have_received(:find_each)
      expect(block_called_with).to eq([ :a, :b ])
    end

    it "swallows errors per-row when iterating via `with_iterator: :find_each`" do
      rows = double("rows")
      allow(rows).to receive(:find_each).and_yield(:a).and_yield(:b).and_yield(:c)

      seen = []
      described_class.call(rows, label: "T", logger: logger, with_iterator: :find_each) do |row|
        raise "bad #{row}" if row == :b

        seen << row
      end
      expect(seen).to eq([ :a, :c ])
      expect(logger).to have_received(:warn).with(a_string_matching(/\[T\].*bad b/))
    end
  end
end
