# frozen_string_literal: true

module Pito
  module MessageBuilder
    module Help
      # Shared builder for the follow-up-actions help message.
      #
      # Both the `help` chat tool and the `#help` hashtag handler call this builder
      # to produce an IDENTICAL System message payload.
      #
      # == Output shape
      #
      # Returns a Hash with:
      #   body     — a single Pito::Copy variant (intro line)
      #   sections — one section per entity group, title UPPERCASE, each section
      #              has rows of { key: "<target>", value: "<actions>" }
      #
      # == Grouping
      #
      # Targets are grouped by their entity prefix:
      #   game_*         → "GAME"
      #   video_*        → "VIDEO"
      #   channel_*      → "CHANNEL"
      #   theme_*        → "THEME"
      #   confirmation_* → "CONFIRMATION"
      #   (anything else → "OTHER")
      #
      # The group order is fixed (GAME, VIDEO, CHANNEL, THEME, CONFIRMATION, OTHER)
      # so new handlers slot into the right bucket automatically. The list is driven
      # entirely by Pito::FollowUp::Registry.all — adding a new handler makes it
      # appear here without any manual edits.
      module FollowUpActions
        ENTITY_ORDER = %w[GAME VIDEO CHANNEL THEME CONFIRMATION OTHER].freeze

        ENTITY_MAP = {
          "game"         => "GAME",
          "video"        => "VIDEO",
          "channel"      => "CHANNEL",
          "theme"        => "THEME",
          "confirmation" => "CONFIRMATION"
        }.freeze

        class << self
          # @return [Hash] system payload with body + sections
          def call
            {
              "body"     => Pito::Copy.render("pito.copy.help.chat.body"),
              "sections" => build_sections
            }
          end

          private

          # Groups the follow-up registry into ordered entity buckets and builds the
          # sections array.  Each section has:
          #   title — entity label in ALL CAPS (rendered yellow by the system component)
          #   rows  — one row per target id: { key: target_id, value: actions joined }
          def build_sections
            grouped = Hash.new { |h, k| h[k] = [] }

            Pito::FollowUp::Registry.all.each do |target_id, handler_class|
              next if handler_class.respond_to?(:internal?) && handler_class.internal?

              entity  = entity_for(target_id)
              actions = Pito::FollowUp::Registry.presentable_actions_for(target_id)
              label   = actions.any? ? actions.map { |a| display_action_token(a) }.join(", ") : "—"
              grouped[entity] << { "key" => target_id, "value" => label }
            end

            ENTITY_ORDER.filter_map do |entity|
              rows = grouped[entity]
              next if rows.empty?

              {
                "title" => entity,
                "rows"  => rows.sort_by { |r| r["key"] }
              }
            end
          end

          def entity_for(target_id)
            prefix = target_id.to_s.split("_").first
            ENTITY_MAP.fetch(prefix, "OTHER")
          end

          # @ai's action token carries the ACTIVE model parenthesized on
          # (Ai::Client.ai_label) — every other action renders as itself.
          def display_action_token(action)
            action.to_s == "@ai" ? ::Ai::Client.ai_label : action.to_s
          end
        end
      end
    end
  end
end
