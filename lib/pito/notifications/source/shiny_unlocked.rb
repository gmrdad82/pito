# frozen_string_literal: true

module Pito
  module Notifications
    module Source
      # One "success" notification per newly-unlocked Achievement ("shiny").
      #
      # Called by AchievementsRefreshJob after its full gather phase — once for
      # each Achievement record inserted during the run, in ascending-threshold
      # order so the owner sees milestones in natural progression. Also called
      # by any real-time (non-batch) unlock path, where each shiny still fires
      # its own individual webhook immediately.
      #
      # Message format:
      #   "<entity name> earned a shiny — <Witty Name> (<compact value> <Label>)"
      #
      # The witty name comes from `pito.copy.shinies.steps_game.<threshold>` for
      # Game achievables and `pito.copy.shinies.steps.<threshold>` otherwise.
      #
      # == Batch callers and the digest webhook
      #
      # AchievementsRefreshJob unlocks many shinies per run and wants ONE
      # combined `Pito::Notifications::WebhookDigest` message instead of a
      # per-shiny webhook flood. It passes `skip_webhook: true` to `report!` —
      # the in-app Notification and mini-status broadcast still happen, only
      # the individual `NotificationWebhookDeliverJob` is suppressed — and uses
      # `digest_row` to collect the `[headline, entity]` pair for each shiny
      # into the digest `rows`. The `skip_webhook:` default (false) leaves
      # every real-time caller's per-shiny webhook untouched.
      #
      # == Headline carries the metric + threshold (T31)
      #
      # The witty step name alone ("Score!") is GENERIC per threshold — every
      # metric hits its own "Score!" at 20 — so the name can't identify what
      # was actually achieved. `headline` is the one place that composes
      # "<witty name> (<compact threshold> <metric label>)", e.g.
      # "Score! (20 Likes)"; both `build_message` (the in-app /notifications
      # message, and the source `notification.message` a real-time single
      # webhook delivery formats via `WebhookFormatter`) and `digest_row`
      # (the batch digest's `col1`, formatted into the Slack/Discord table by
      # `WebhookDigest`) call it, so all three surfaces stay in lockstep.
      module ShinyUnlocked
        module_function

        # @param achievement  [Achievement]
        # @param skip_webhook [Boolean] suppress this Notification's individual
        #   webhook delivery (batch callers send one digest instead — see the
        #   class doc above). Defaults to false so real-time callers keep
        #   firing their own webhook the moment a shiny unlocks.
        # @return [Notification]
        def report!(achievement, skip_webhook: false)
          Notification.create!(
            message:      build_message(achievement),
            level:        "shiny",
            title:        Pito::Copy.render("pito.copy.notifications.shiny_unlocked_title"),
            skip_webhook: skip_webhook
          )
        end

        # The `[headline, entity display name]` pair for one unlocked
        # Achievement — the 2-column row shape `WebhookDigest` wants (col1 =
        # the achievement + what it measured, col2 = who earned it). Used by
        # batch callers building digest `rows`; see the class doc above.
        # @param achievement [Achievement]
        # @return [Array(String, String)]
        def digest_row(achievement)
          [ headline(achievement), display_name(achievement.achievable) ]
        end

        # "<witty name> (<compact threshold> <metric label>)", e.g.
        # "Score! (20 Likes)" — see the class doc's "Headline carries the
        # metric + threshold" section. The single formatter both the
        # in-app/webhook message and the digest row build on.
        # @param achievement [Achievement]
        # @return [String]
        def headline(achievement)
          witty   = witty_name(achievement)
          compact = Pito::Formatter::CompactCount.call(achievement.threshold)
          label   = Pito::Achievements::Label.for(achievement.metric, count: achievement.threshold)

          "#{witty} (#{compact} #{label})"
        end

        def build_message(achievement)
          entity = display_name(achievement.achievable)

          "#{entity} earned a shiny — #{headline(achievement)}"
        end
        private_class_method :build_message

        def display_name(achievable)
          case achievable
          when ::Channel then achievable.at_handle
          else                achievable.title
          end
        end
        private_class_method :display_name

        def witty_name(achievement)
          namespace = achievement.achievable_type == "Game" ? "steps_game" : "steps"
          Pito::Copy.render("pito.copy.shinies.#{namespace}.#{achievement.threshold}")
        end
        private_class_method :witty_name
      end
    end
  end
end
