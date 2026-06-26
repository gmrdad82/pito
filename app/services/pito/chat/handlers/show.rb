# frozen_string_literal: true

# Handler for the `show game <id>` / `show video <id>` chat verb.
#
# Resolves a single game or video by **ID only** (`#123` or `123`) —
# title (ILIKE) lookup is intentionally disabled (id_only_resolution!).
# Emits the appropriate detail message (follow-up-able).
# Unknown reference → witty not-found via `Pito::Copy`. No reference → a usage
# hint (the no-arg picker fast-path is wired in `ChatController`).
module Pito
  module Chat
    module Handlers
      class Show < Pito::Chat::Handler
        self.verb = :show
        self.description_key = "pito.chat.show.descriptions.show"
        id_only_resolution!

        # `game`/`games` are noun fillers the user types but that carry no value
        # when resolving a game.
        GAME_NOUN_FILLERS  = %w[game games].freeze

        # `vid`/`vids` (canonical) and `video`/`videos` (aliases) are noun fillers
        # for the video branch.
        VIDEO_NOUN_FILLERS = %w[vid vids video videos].freeze

        # `channel`/`channels` route to the channel branch — resolved by @handle
        # (NOT a numeric id), mirroring `shinies channel @handle`.
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

        # ── Channel branch (`show channel @handle`) ──────────────────────────────

        # Free-chat: a channel noun token present in the body? (show channel is a
        # chat verb; the channel @handle is resolved separately, not by id.)
        def channel_noun?
          message.body_tokens.any? { |t| CHANNEL_NOUN_FILLERS.include?(t.value.to_s.downcase) }
        end

        def handle_channel
          channel = resolve_channel
          return needs_ref if channel == :needs_ref
          return channel_not_found(channel_ref) if channel.nil?

          # :system detail card, then — when the channel has videos — the repliable
          # :enhanced vids list (video_list follow-up target), then LAST the channel
          # analytics glance (pending state, filled async by AnalyticsFillJob over
          # the shift+space period; channel-level metrics need no linked videos).
          events = [
            { kind: :system, payload: Pito::MessageBuilder::Channel::Detail.call(channel, conversation:) }
          ]
          events << { kind: :enhanced, payload: Pito::MessageBuilder::Channel::Videos.call(channel, conversation:) } if channel.videos.any?
          events << { kind: :enhanced, payload: Pito::MessageBuilder::Analytics::Enhanced.pending(channel, period: analytics_period, conversation:) }

          Pito::Chat::Result::Ok.new(events: events)
        end

        # Resolve the channel by @handle (case-insensitive, @-agnostic).
        def resolve_channel
          handle = channel_ref
          return :needs_ref if handle.blank?

          norm = handle.to_s.sub(/\A@+/, "").downcase
          ::Channel.find_by("LOWER(REPLACE(handle, '@', '')) = LOWER(?)", norm)
        end

        # The @handle token after stripping the verb + channel noun.
        def channel_ref
          extract_ref_from(message.raw, CHANNEL_NOUN_FILLERS)
        end

        def channel_not_found(ref)
          Pito::Chat::Result::Ok.new(consume: false, events: [
            { kind: :system, payload: Pito::MessageBuilder::Text.call("pito.copy.channels.not_found", handle: ref) }
          ])
        end

        # ── Video branch ───────────────────────────────────────────────────────

        def handle_video
          video = resolve_target(::Video, id_key: :video_id, noun_fillers: VIDEO_NOUN_FILLERS)
          return needs_ref if video == :needs_ref
          return video_not_found(target_ref(VIDEO_NOUN_FILLERS, id_key: :video_id)) if video.nil?

          # Standard detail card (follow-up-able), then — when the video has a
          # linked game — the repliable slim linked-game card (game_detail
          # follow-up target), then the analytics :enhanced message: emitted in
          # its PENDING state (instant intro), filled async by AnalyticsFillJob.
          # The linked-game card is omitted entirely when the video has none.
          # Identical events whether typed in free chat or via a `#<handle>` reply.
          events = [
            { kind: :system, payload: Pito::MessageBuilder::Video::Detail.call(video, conversation:) }
          ]
          if video.linked_games.first
            events << { kind: :enhanced, payload: Pito::MessageBuilder::Video::LinkedGame.call(video, conversation:) }
          end
          events << { kind: :enhanced, payload: Pito::MessageBuilder::Analytics::Enhanced.pending(video, period: analytics_period, conversation:) }

          Pito::Chat::Result::Ok.new(events: events)
        end

        # consume: false — on a `#<handle>` reply a not-found must NOT consume the
        # source list, so the owner can retry the reply without repeating it.
        def video_not_found(ref)
          Pito::Chat::Result::Ok.new(consume: false, events: [
            { kind: :system, payload: Pito::MessageBuilder::Text.call("pito.copy.videos.not_found", ref: ref) }
          ])
        end

        # ── Game branch ────────────────────────────────────────────────────────

        def handle_game
          game = resolve_target(::Game, id_key: :game_id, noun_fillers: GAME_NOUN_FILLERS)
          return needs_ref if game == :needs_ref
          return game_not_found(target_ref(GAME_NOUN_FILLERS, id_key: :game_id)) if game.nil?

          # Order: the Standard detail message (follow-up-able), then — when the
          # game has linked videos — the repliable linked-videos list table
          # (video_list follow-up target); then the Enhanced recommendations
          # message (channel suggestions + similar games); then LAST the analytics
          # :enhanced message (pending state, filled async — aggregated across the
          # linked videos). Analytics goes last because it resolves slowest (the
          # thinking spinner stays up until the background fill job completes), so
          # the recommendations land first. Linked-videos + analytics are omitted
          # when the game has none. Identical whether typed or via a `#<handle>` reply.
          events = [
            { kind: :system, payload: Pito::MessageBuilder::Game::Detail.call(game, conversation:) }
          ]
          events << { kind: :enhanced, payload: Pito::MessageBuilder::Game::LinkedVideos.call(game, conversation:) } if game.linked_videos.any?
          events << { kind: :enhanced, payload: Pito::MessageBuilder::Game::Enhanced.call(game) }
          events << { kind: :enhanced, payload: Pito::MessageBuilder::Analytics::Enhanced.pending(game, period: analytics_period, conversation:) } if game.linked_videos.any?

          Pito::Chat::Result::Ok.new(events: events)
        end

        # consume: false — see video_not_found: a not-found reply stays repliable.
        def game_not_found(ref)
          Pito::Chat::Result::Ok.new(consume: false, events: [
            { kind: :system, payload: Pito::MessageBuilder::Text.call("pito.copy.games.not_found", ref: ref) }
          ])
        end

        # ── Shared helpers ─────────────────────────────────────────────────────

        # Returns the explicit period param when present; falls back to the
        # conversation's persisted stats_period so nil never reaches the analytics layer.
        def analytics_period = period.presence || conversation.stats_period

        def needs_ref
          Pito::Chat::Result::Error.new(message_key: "pito.chat.show.needs_ref", message_args: {})
        end
      end
    end
  end
end
