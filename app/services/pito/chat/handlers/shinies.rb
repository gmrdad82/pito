# frozen_string_literal: true

module Pito
  module Chat
    module Handlers
      # Handler for the `shinies` chat verb.
      #
      # Forms:
      #   shinies channel @handle  — channel by @handle
      #   shinies vid <id|#id>     — video by numeric id or #id ref
      #   shinies game <id|#id>    — game by numeric id or #id ref
      #
      # Context-aware reply: when invoked as a follow-up (reply to list/detail events
      # for games, videos, or channels), the target entity is inferred from the
      # source event payload (game_id / video_id) or, for channels, from the
      # explicit @handle carried in follow_up.rest.
      class Shinies < Pito::Chat::Handler
        self.verb = :shinies
        self.description_key = "pito.chat.shinies.descriptions.shinies"
        id_only_resolution!

        GAME_NOUN_FILLERS    = %w[game games].freeze
        VIDEO_NOUN_FILLERS   = %w[vid vids video videos].freeze
        CHANNEL_NOUN_FILLERS = %w[channel channels].freeze

        def call
          if channel_noun?
            handle_channel
          elsif video_target?(VIDEO_NOUN_FILLERS)
            handle_video
          else
            handle_game
          end
        end

        private

        # ── Entity detection ────────────────────────────────────────────────────

        # In follow-up context: the source event's reply_target determines the entity
        # type.  In free-chat: look for a channel noun token in the body tokens.
        def channel_noun?
          return reply_target.to_s.start_with?("channel") if follow_up?

          message.body_tokens.any? { |t| CHANNEL_NOUN_FILLERS.include?(t.value.to_s.downcase) }
        end

        # ── Handlers ────────────────────────────────────────────────────────────

        def handle_channel
          channel = resolve_channel
          return needs_ref if channel == :needs_ref
          return channel_not_found(channel_ref) if channel.nil?

          shinies_event(channel)
        end

        def handle_video
          video = resolve_target(::Video, id_key: :video_id, noun_fillers: VIDEO_NOUN_FILLERS)
          return needs_ref if video == :needs_ref
          return entity_not_found("pito.copy.videos.not_found", target_ref(VIDEO_NOUN_FILLERS, id_key: :video_id)) if video.nil?

          shinies_event(video)
        end

        def handle_game
          game = resolve_target(::Game, id_key: :game_id, noun_fillers: GAME_NOUN_FILLERS)
          return needs_ref if game == :needs_ref
          return entity_not_found("pito.copy.games.not_found", target_ref(GAME_NOUN_FILLERS, id_key: :game_id)) if game.nil?

          shinies_event(game)
        end

        # ── Resolution helpers ───────────────────────────────────────────────────

        def shinies_event(entity)
          Pito::Chat::Result::Ok.new(events: [
            { kind: :system, payload: Pito::MessageBuilder::Shinies.call(entity, conversation:) }
          ])
        end

        # Resolve the channel entity — in follow-up context uses follow_up.rest;
        # in free-chat uses the raw input after stripping verb + channel noun.
        def resolve_channel
          handle = channel_ref
          return :needs_ref if handle.blank?

          norm = handle.to_s.sub(/\A@+/, "").downcase
          ::Channel.find_by("LOWER(REPLACE(handle, '@', '')) = LOWER(?)", norm)
        end

        # The raw channel ref (the @handle token) from either follow_up.rest or message.raw.
        def channel_ref
          if follow_up?
            strip_noun(follow_up.rest.to_s, CHANNEL_NOUN_FILLERS)
          else
            extract_ref_from(message.raw, CHANNEL_NOUN_FILLERS)
          end
        end

        # ── Error results ────────────────────────────────────────────────────────

        def needs_ref
          Pito::Chat::Result::Error.new(
            message_key: "pito.chat.shinies.needs_ref",
            message_args: {}
          )
        end

        def entity_not_found(copy_key, ref)
          Pito::Chat::Result::Ok.new(events: [
            { kind: :system, payload: Pito::MessageBuilder::Text.call(copy_key, ref: ref) }
          ])
        end

        def channel_not_found(ref)
          Pito::Chat::Result::Ok.new(events: [
            { kind: :system, payload: Pito::MessageBuilder::Text.call("pito.copy.channels.not_found", handle: ref) }
          ])
        end
      end
    end
  end
end
