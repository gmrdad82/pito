# frozen_string_literal: true

module Pito
  module MessageBuilder
    module Video
      # Builds the `schedule <id> slate` upcoming-schedule planning view.
      #
      # ONE combined :system list of SCHEDULED videos (privacy_status :private + a
      # FUTURE publish_at), excluding the reference vid, filtered by the
      # conversation's channel scope (shift+tab) and bounded by its stats period
      # (shift+space), ordered by go-live (publish_at asc).
      #
      # Columns: # (id), Title, Channel, Go-live — the last a HUMAN relative date
      # ("in 3 hours", "tomorrow at noon", "on 1st of March") via the slate-only
      # `:scheduled` column, so near vs far reads at a glance without a week/rest
      # split. Reuses Video::List, so the table stays repliable (show/sort/with/…).
      # An empty period yields witty copy.
      module Slate
        module_function

        COLUMNS   = %i[channel scheduled].freeze
        WEEK_DAYS = 7

        # period token → window length in days. `lifetime` ⇒ no upper bound; an
        # unrecognised / discrete future period (e.g. "May") collapses to a
        # week-only window, where an empty result is a perfectly valid outcome.
        PERIOD_DAYS = { "7d" => 7, "28d" => 28, "1m" => 30, "3m" => 90, "1y" => 365 }.freeze

        # @return [Array<Hash>] a single event ({ kind:, payload: }).
        def call(exclude_id:, channel_scope:, period:, conversation:, now: Time.current)
          window_end = window_end_for(period, now)
          videos     = scheduled_videos(exclude_id:, channel_scope:, now:, window_end:)
          [ slate_event(videos, conversation) ]
        end

        # ── Window ────────────────────────────────────────────────────────────

        def window_end_for(period, now)
          token = period.to_s
          return nil if token == "lifetime"

          days = PERIOD_DAYS[token] || WEEK_DAYS # unknown/discrete → week only
          now + days.days
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

        # ── Event ─────────────────────────────────────────────────────────────

        def slate_event(videos, conversation)
          payload =
            if videos.any?
              list_payload(videos, conversation)
            else
              Pito::MessageBuilder::Text.call("pito.copy.schedule.slate.empty")
            end
          { kind: :system, payload: payload }
        end

        def list_payload(videos, conversation)
          payload = Pito::MessageBuilder::Video::List.call(videos, conversation: conversation, columns: COLUMNS)
          payload["body"] = Pito::Copy.render("pito.copy.schedule.slate.lined_up", count: videos.size)
          payload
        end
      end
    end
  end
end
