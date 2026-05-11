# Phase 15 §1 — Calendar Data Model.
#
# Iterates `MilestoneRule.where(enabled: true, fired_at: nil)`, reads
# the metric per `(scope_type, scope_id, metric, metric_window)`,
# compares against `threshold` per `direction`, and fires the rule on
# crossing. The metric reader is an injectable dependency — Phase 13
# (analytics) replaces the default stub.
#
# Per-rule failures are rescued so a single bad rule does not block the
# rest of the evaluation cycle.
module Calendar
  class MilestoneEvaluator
    def initialize(metric_reader: DefaultMetricReader.new)
      @metric_reader = metric_reader
    end

    def evaluate_all!
      # 2026-05-11 — iterate-and-soft-fail pattern lives in
      # `Pito::SafeEach`. The wrapper logs `[MilestoneEvaluator]
      # swallowed <class>: <msg> (row=<id>)` and continues on
      # StandardError so one bad rule does not block the rest of the
      # evaluation cycle.
      rules = MilestoneRule.where(enabled: true, fired_at: nil).find_each
      Pito::SafeEach.call(rules, label: "MilestoneEvaluator") do |rule|
        evaluate(rule)
      end
    end

    def evaluate(rule)
      value = @metric_reader.read(
        scope_type: rule.scope_type,
        scope_id:   rule.scope_id,
        metric:     rule.metric,
        window:     rule.metric_window
      )
      return if value.nil?

      crossed = case rule.direction
      when "cross_up"   then value >= rule.threshold
      when "cross_down" then value <= rule.threshold
      end
      return unless crossed

      rule.fire!(metric_value: value)
    end

    # Phase 13 (analytics) replaces this stub. The injection point lets
    # the test suite use a hash-backed reader.
    class DefaultMetricReader
      def read(**_args)
        nil
      end
    end
  end
end
