# frozen_string_literal: true

module Pito
  module Notifications
    module Source
      # One "success" notification per newly-unlocked Achievement ("shiny").
      #
      # Called by AchievementsRefreshJob after its full gather phase — once for
      # each Achievement record inserted during the run, in ascending-threshold
      # order so the owner sees milestones in natural progression.
      #
      # Message format:
      #   "<entity name> earned a shiny — <Witty Name> (<compact value> <Label>)"
      #
      # The witty name comes from `pito.copy.shinies.steps_game.<threshold>` for
      # Game achievables and `pito.copy.shinies.steps.<threshold>` otherwise.
      module ShinyUnlocked
        module_function

        # @param achievement [Achievement]
        # @return [Notification]
        def report!(achievement)
          Notification.create!(message: build_message(achievement), level: "shiny")
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
