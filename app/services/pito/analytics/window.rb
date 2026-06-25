# frozen_string_literal: true

module Pito
  module Analytics
    # Value object describing a stats period window: date range, comparable
    # prior interval, human label, and cycle metadata.
    #
    # == Usage
    #
    #   window = Pito::Analytics::Window.for("7d", reference_date: Date.current)
    #   window.start_date  # => Date
    #   window.end_date    # => Date  (inclusive)
    #   window.prev_start  # => Date | nil
    #   window.prev_end    # => Date | nil
    #   window.label       # => "7d"
    #   window.comparable? # => true
    #   window.token       # => "7d"
    #
    # == Determinism
    #
    # `reference_date` is treated as "today" — Date.current is never called
    # inside the class. Pass a fixed date in specs and use Date.current at the
    # call site in production code.
    #
    # == Tokens
    #
    # Rolling windows:   7d, 28d, 3m, 1y
    # Partial calendar:  m0 (current partial month), y0 (current partial year)
    # Full calendar:     m1 (last full month), m2 (month before that)
    #                    y1 (last full year)
    # Special:           lifetime
    #
    # Note: "1m" is intentionally absent from CYCLE — 28d is the rolling-month
    # token and m0/m1/m2 cover calendar months.
    class Window
      # Ordered token list for the shift+space UI cycle.
      CYCLE = %w[7d 28d 3m 1y lifetime m0 m1 m2 y0 y1].freeze

      attr_reader :token, :start_date, :end_date, :prev_start, :prev_end, :label

      # Build a Window for the given token.
      # A nil or blank token raises ArgumentError — callers must supply an explicit
      # period; the canonical default lives at the conversation level.
      #
      # @param token              [String]       one of CYCLE
      # @param reference_date     [Date]         treated as "today"
      # @param channel_created_on [Date, nil]    start date for :lifetime
      # @return [Window]
      # @raise [ArgumentError] for nil/blank tokens or unknown tokens
      def self.for(token, reference_date:, channel_created_on: nil)
        new(token, reference_date: reference_date, channel_created_on: channel_created_on)
      end

      # Array of { token:, label: } hashes for building the UI cycle list.
      # Labels are dynamic (month/year names depend on reference_date).
      #
      # @param reference_date [Date]
      # @return [Array<Hash>]
      def self.cycle(reference_date:)
        CYCLE.map do |t|
          w = self.for(t, reference_date: reference_date)
          { token: t, label: w.label }
        end
      end

      def comparable?
        @comparable
      end

      # Days a window's end_date must be in the past before its data is treated as
      # finalized. YouTube finalizes estimated metrics in ~2–3 days; the 7-day
      # buffer absorbs late revisions / timezone edges (docs/claude/0.8.0.md).
      FINALIZED_AFTER = 7

      # Freeze math as class methods so both a Window and its PreviousRange share it.
      def self.finalized?(end_date:, as_of:)
        end_date <= as_of - FINALIZED_AFTER
      end

      def self.expires_at_for(end_date:, now:, live_ttl: 1.hour)
        finalized?(end_date:, as_of: now.to_date) ? nil : now + live_ttl
      end

      # A duck-typed window covering the prior comparable range — same interface
      # Primitives.fetch needs (start_date / end_date / token / expires_at_for).
      PreviousRange = Data.define(:start_date, :end_date, :token) do
        def expires_at_for(now:, live_ttl: 1.hour)
          Pito::Analytics::Window.expires_at_for(end_date:, now:, live_ttl:)
        end
      end

      # True once this window's end_date is far enough in the past that YouTube
      # data can no longer change — so its primitives/results can be cached forever.
      #
      # @param as_of [Date] treated as "today" (pass Date.current at the call site)
      def finalized?(as_of:)
        self.class.finalized?(end_date:, as_of:)
      end

      # Cache expiry for this window's primitives / accumulated results:
      #   finalized → nil   (never expires; the period is frozen)
      #   live      → now + live_ttl  (recent days still move)
      #
      # @param now      [Time] treated as "now" (pass Time.current at the call site)
      # @param live_ttl [ActiveSupport::Duration] TTL for non-finalized windows
      def expires_at_for(now:, live_ttl: 1.hour)
        self.class.expires_at_for(end_date:, now:, live_ttl:)
      end

      # The prior comparable window (for trend baselines), or nil when this window
      # isn't comparable (e.g. lifetime). Its token is suffixed `-prev` so its
      # primitive rows never collide with the current window's.
      def previous
        return nil unless comparable?

        PreviousRange.new(start_date: prev_start, end_date: prev_end, token: "#{token}-prev")
      end

      private

      def initialize(token, reference_date:, channel_created_on: nil)
        @token = token
        compute!(reference_date, channel_created_on)
      end

      def compute!(ref, channel_created_on) # rubocop:disable Metrics/MethodLength
        case @token
        when "7d"   then rolling_days!(ref, 7, label: "7d")
        when "28d"  then rolling_days!(ref, 28, label: "28d")
        when "3m"   then rolling_months!(ref, 3, label: "3m")
        when "1y"   then rolling_months!(ref, 12, label: "1y")
        when "lifetime" then lifetime!(ref, channel_created_on)
        when "m0"   then partial_month!(ref)
        when "m1"   then full_month!(ref, offset: 1)
        when "m2"   then full_month!(ref, offset: 2)
        when "y0"   then partial_year!(ref)
        when "y1"   then full_year!(ref, offset: 1)
        else
          raise ArgumentError,
                "unknown analytics token: #{@token.inspect} (expected one of #{CYCLE.inspect})"
        end
      end

      # Rolling N-day window ending on ref (inclusive).
      # prev = the N days immediately before.
      def rolling_days!(ref, n, label:)
        @end_date   = ref
        @start_date = ref - (n - 1)
        @prev_end   = @start_date - 1
        @prev_start = @prev_end - (n - 1)
        @label      = label
        @comparable = true
      end

      # Rolling N-month window ending on ref (inclusive).
      # start = (ref << N) + 1 day.
      # prev = the N months immediately before that window.
      def rolling_months!(ref, n, label:)
        @end_date   = ref
        @start_date = (ref << n) + 1
        @prev_end   = @start_date - 1
        @prev_start = (@prev_end << n) + 1
        @label      = label
        @comparable = true
      end

      def lifetime!(ref, channel_created_on)
        @start_date = channel_created_on || Date.new(2005, 1, 1)
        @end_date   = ref
        @prev_start = nil
        @prev_end   = nil
        @label      = "lifetime"
        @comparable = false
      end

      # m0: current (partial) month — from bom to ref.
      # prev = the same elapsed span in the prior month (clamped to that month's end).
      def partial_month!(ref)
        bom          = ref.beginning_of_month
        prev_bom     = bom << 1
        elapsed_days = ref.day - 1
        raw_prev_end = prev_bom + elapsed_days

        @start_date = bom
        @end_date   = ref
        @prev_start = prev_bom
        @prev_end   = [ raw_prev_end, prev_bom.end_of_month ].min
        @label      = bom.strftime("%b '%y")
        @comparable = true
      end

      # m1 / m2: a full calendar month, `offset` months back from current bom.
      # prev = the full month immediately before it.
      def full_month!(ref, offset:)
        bom          = ref.beginning_of_month
        target_bom   = bom << offset
        prev_bom     = bom << (offset + 1)

        @start_date = target_bom
        @end_date   = target_bom.end_of_month
        @prev_start = prev_bom
        @prev_end   = prev_bom.end_of_month
        @label      = target_bom.strftime("%b '%y")
        @comparable = true
      end

      # y0: current (partial) year — from boy to ref.
      # prev = the same elapsed span (days) in the prior year.
      def partial_year!(ref)
        boy     = ref.beginning_of_year
        elapsed = (ref - boy).to_i
        prev_boy = Date.new(ref.year - 1, 1, 1)

        @start_date = boy
        @end_date   = ref
        @prev_start = prev_boy
        @prev_end   = prev_boy + elapsed
        @label      = ref.year.to_s
        @comparable = true
      end

      # y1: previous full calendar year.
      # prev = the year before that (full).
      def full_year!(ref, offset:)
        target_year = ref.year - offset

        @start_date = Date.new(target_year, 1, 1)
        @end_date   = Date.new(target_year, 12, 31)
        @prev_start = Date.new(target_year - 1, 1, 1)
        @prev_end   = Date.new(target_year - 1, 12, 31)
        @label      = target_year.to_s
        @comparable = true
      end
    end
  end
end
