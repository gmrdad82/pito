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
      # `digest_row` to collect the `[witty, entity]` pair for each shiny into
      # the digest `rows`. The `skip_webhook:` default (false) leaves every
      # real-time caller's per-shiny webhook untouched.
      module ShinyUnlocked
        module_function

        # @param achievement  [Achievement]
        # @param skip_webhook [Boolean] suppress this Notification's individual
        #   webhook delivery (batch callers send one digest instead — see the
        #   class doc above). Defaults to false so real-time callers keep
        #   firing their own webhook the moment a shiny unlocks.
        # @return [Notification]
        def report!(achievement, skip_webhook: false)
          Notification.create!(message: build_message(achievement), level: "shiny", skip_webhook: skip_webhook)
        end

        # The `[witty achievement name, entity display name]` pair for one
        # unlocked Achievement — the 2-column row shape `WebhookDigest` wants
        # (col1 = the achievement, col2 = who earned it). Used by batch
        # callers building digest `rows`; see the class doc above.
        # @param achievement [Achievement]
        # @return [Array(String, String)]
        def digest_row(achievement)
          [ witty_name(achievement), display_name(achievement.achievable) ]
        end

        def build_message(achievement)
          entity  = display_name(achievement.achievable)
          witty   = witty_name(achievement)
          compact = Pito::Formatter::CompactCount.call(achievement.threshold)
          label   = Pito::Achievements::Label.for(achievement.metric, count: achievement.threshold)

          "#{entity} earned a shiny — #{witty} (#{compact} #{label})"
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
