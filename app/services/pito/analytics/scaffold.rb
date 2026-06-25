# frozen_string_literal: true

module Pito
  module Analytics
    # The `0`/`1` "can we pull it?" scaffold for the `analyze` messages. For a scope
    # (channel groups) + window + role + level, it fetches each needed report group
    # (via Primitives; retention is the single-video special case) and reports, per
    # metric, whether data came back (`true` = 1) or not (`false` = 0).
    #
    # This is the TEMPORARY uniform renderer that proves the fan-out + verb +
    # with/without work end-to-end, before each metric earns its own bespoke
    # component (owner "revisit"). Metrics sharing one report group share its flag.
    module Scaffold
      module_function

      # @param groups [Array<[Channel, Array<String> | :channel]>]
      # @param window [Pito::Analytics::Window]
      # @param role   [Symbol] :system | :enhanced
      # @param level  [Symbol] :channel | :vid | :game
      # @return [Hash{Symbol=>Boolean}] metric => data-pulled?
      def for(groups:, window:, role:, level:)
        report_ok = {} # report group => bool, memoised so shared-report metrics agree
        MetricOrder.for(role:, level:).index_with do |metric|
          rep = MetricOrder.report(metric)
          report_ok[rep] = pulled?(groups:, window:, report: rep) unless report_ok.key?(rep)
          report_ok[rep]
        end
      end

      def pulled?(groups:, window:, report:)
        data =
          if report == "retention"
            retention_data(groups:, window:)
          else
            Pito::Analytics::Primitives.fetch(groups:, window:, report:)
          end
        data.present? && data.values.any?(&:present?)
      rescue StandardError => e
        Rails.logger.warn("[Analytics::Scaffold] #{report}: #{e.class}: #{e.message}")
        false
      end

      # retention is single-video only (no comma list) — probe the first video in
      # the scope (MetricOrder only includes retention at :vid level).
      def retention_data(groups:, window:)
        channel, subjects = groups.find { |_ch, subs| subs.is_a?(Array) && subs.any? }
        return {} unless channel

        vid  = subjects.first
        rows = ::Channel::Youtube::AnalyticsClient
          .new(channel.youtube_connection)
          .retention(channel_id: channel.youtube_channel_id, start_date: window.start_date, end_date: window.end_date, video: vid)
        { vid => rows }
      end
    end
  end
end
