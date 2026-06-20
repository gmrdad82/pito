# frozen_string_literal: true

module Pito
  module MessageBuilder
    module Video
      # Builds the `schedule <id> slate` upcoming-schedule planning view.
      #
      # Lists SCHEDULED videos (privacy_status :private + a FUTURE publish_at),
      # excluding the reference vid, filtered by the conversation's channel scope
      # (shift+tab) and bounded by its stats period (shift+space):
      #
      #   * a :system WEEK message (next 7 days) — ALWAYS emitted.
      #   * a :enhanced REST message (day 8 … end of period) — ONLY when the period
      #     is wider than 7 days AND the rest window holds scheduled vids.
      #
      # Both reuse Video::List with the [channel, scheduled, game] columns, so the
      # table looks exactly like `list videos`. Empty windows yield witty copy.
      module Slate
        module_function

        COLUMNS   = %i[channel scheduled game].freeze
        WEEK_DAYS = 7

        # period token → window length in days. `lifetime` ⇒ no upper bound; an
        # unrecognised / discrete future period (e.g. "May") collapses to a
        # week-only window, where an empty rest is a perfectly valid result.
        PERIOD_DAYS = { "7d" => 7, "28d" => 28, "1m" => 30, "3m" => 90, "1y" => 365 }.freeze

        # @return [Array<Hash>] one or two events ({ kind:, payload: }).
        def call(exclude_id:, channel_scope:, period:, conversation:, now: Time.current)
          window_end = window_end_for(period, now)
          videos     = scheduled_videos(exclude_id:, channel_scope:, now:, window_end:)

          week_cutoff = now + WEEK_DAYS.days
          week, rest  = videos.partition { |v| v.publish_at <= week_cutoff }

          events = [ week_event(week, conversation) ]
          events << rest_event(rest, conversation) if beyond_week?(period, now, window_end) && rest.any?
          events
        end

        # ── Window ────────────────────────────────────────────────────────────

        def window_end_for(period, now)
          token = period.to_s
          return nil if token == "lifetime"

          days = PERIOD_DAYS[token] || WEEK_DAYS # unknown/discrete → week only
          now + days.days
        end

        def beyond_week?(period, now, window_end)
          return true if period.to_s == "lifetime"

          window_end.present? && window_end > now + WEEK_DAYS.days
        end

        # ── Query ─────────────────────────────────────────────────────────────

        def scheduled_videos(exclude_id:, channel_scope:, now:, window_end:)
          scope = ::Video.where(privacy_status: :private).where("publish_at > ?", now)
          scope = scope.where("publish_at <= ?", window_end) if window_end
          scope = scope.where.not(id: exclude_id) if exclude_id.present?
          scope = filter_channel(scope, channel_scope)
          scope.includes(:channel).order(:publish_at).to_a
        end

        # Scope to a single channel by handle (tolerant of a leading "@" and case);
        # "@all" / blank means every channel.
        def filter_channel(scope, channel_scope)
          return scope if channel_scope.blank? || channel_scope == "@all"

          target = channel_scope.to_s.delete_prefix("@").downcase
          ids    = ::Channel.all.select { |c| c.handle.to_s.delete_prefix("@").downcase == target }.map(&:id)
          scope.where(channel_id: ids)
        end

        # ── Events ────────────────────────────────────────────────────────────

        def week_event(videos, conversation)
          payload =
            if videos.any?
              list_payload(videos, conversation, "pito.copy.schedule.slate.week")
            else
              Pito::MessageBuilder::Text.call("pito.copy.schedule.slate.empty")
            end
          { kind: :system, payload: payload }
        end

        def rest_event(videos, conversation)
          { kind: :enhanced, payload: list_payload(videos, conversation, "pito.copy.schedule.slate.rest") }
        end

        def list_payload(videos, conversation, intro_key)
          payload = Pito::MessageBuilder::Video::List.call(videos, conversation: conversation, columns: COLUMNS)
          payload["body"] = Pito::Copy.render(intro_key, count: videos.size)
          payload
        end
      end
    end
  end
end
