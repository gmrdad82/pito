# 2026-05-11 — `safe_each` — iterate-and-soft-fail wrapper.
#
# Sweeps / per-row evaluators that want to continue iterating even when
# one item raises (cron sweepers, fan-out evaluators, composite warm-ups)
# repeat the same scaffolding: a `find_each` / `each` loop wrapping the
# real call in a `begin / rescue StandardError / log + next` envelope.
# The reviewer flagged the pattern as duplicated; this helper centralises
# it so call sites read as `Pito::SafeEach.call(rows, label: "...")`
# without re-implementing the rescue.
#
# Contract:
#
#     Pito::SafeEach.call(rows, label: "MilestoneEvaluator") do |row|
#       do_work(row)
#     end
#
# - `rows` must respond to `each` (Array, ActiveRecord::Relation,
#   Enumerable). ActiveRecord callers should pass a relation pre-scoped
#   with `find_each` so the helper inherits the batching semantics.
# - `label:` prefixes every warn line so the operator can grep for the
#   originating site.
# - `logger:` overrides `Rails.logger`. Tests inject a fake.
# - The block runs once per element. Any `StandardError` raised by the
#   block is caught, logged as a warn line, and iteration continues with
#   the next element. Non-StandardError descendants (SystemExit, signals)
#   are NOT caught — they bubble.
# - Returns the input `rows` so callers can chain.
# - Calling without a block raises `ArgumentError`.
module Pito
  module SafeEach
    module_function

    def call(rows, label:, logger: Rails.logger)
      raise ArgumentError, "Pito::SafeEach.call requires a block" unless block_given?

      rows.each do |row|
        yield row
      rescue StandardError => e
        logger.warn(
          "[#{label}] swallowed #{e.class}: #{e.message} (row=#{row_identifier(row)})"
        )
      end

      rows
    end

    # Compact row identifier for the warn line. AR rows surface their
    # primary key; anything else falls back to `inspect.first(80)` so
    # the log line stays bounded.
    def row_identifier(row)
      return row.id if row.respond_to?(:id) && row.id.present?
      row.inspect.to_s[0, 80]
    rescue StandardError
      "?"
    end
  end
end
