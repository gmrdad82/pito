# frozen_string_literal: true

# Handler for the `sync` chat verb — exactly two target forms.
#
#   sync vid|vids|video|videos [#id[,#id…]]
#     Sync YouTube data for videos. With `#id`(s) → sync exactly those videos
#     (ids win; shift+tab scope is ignored). Without ids → sync videos scoped by
#     the shift+tab channel: @all / blank → all channels; @handle → that channel.
#     (`only <ids>` is still accepted as a legacy id form.)
#
#   sync channels [with <item>[,<item>…]]
#     Sync channel fields + stats scoped by the shift+tab channel:
#       @all → all channels; @handle → one channel.
#     The optional `with <items>` clause is a generic comma-list of sync
#     targets — today just `videos` (sync the channel's uploads). Built to
#     extend (analytics lands in 0.8.0).
#
# Channel scope is read from `self.channel` (@all/blank = all channels,
# @handle = one channel; unknown handle = error message).
module Pito
  module Chat
    module Handlers
      class Sync < Pito::Chat::Handler
        self.verb = :sync
        self.description_key = "pito.chat.sync.descriptions.sync"

        # Vocabulary for `with <items>` — mirrors WithColumns pattern.
        # Unknown tokens are silently dropped; new items can be added here
        # without touching the parser.
        WITH_ITEMS_VOCAB = {
          "vid"    => :videos,
          "vids"   => :videos,
          "video"  => :videos,
          "videos" => :videos
        }.freeze

        VIDEO_NOUN_FILLERS   = %w[vid vids video videos].freeze
        GAME_NOUN_FILLERS    = %w[game games gamez].freeze
        CHANNEL_NOUN_FILLERS = %w[channel channels].freeze

        def call
          return handle_follow_up if follow_up?

          raw = message.raw.to_s

          if channels_form?(raw)
            handle_channels(raw)
          elsif videos_form?(raw)
            handle_videos(raw)
          else
            # Fuzzy fallback: try near-miss match against SYNC_TARGETS vocab.
            noun, correction = detect_sync_noun_fuzzy(raw)
            if noun == "channels"
              prepend_typo_note(handle_channels(raw), correction)
            elsif noun == "vids"
              prepend_typo_note(handle_videos(raw), correction)
            else
              needs_ref
            end
          end
        end

        private

        # ── Reply: `#<handle> sync` on a detail card ─────────────────────────────
        #
        # A bare `sync` reply syncs THAT card's entity — the source event's
        # reply_target fixes which (vid / channel / game). Any trailing args are
        # ignored: the context is unambiguous.
        def handle_follow_up
          case reply_target
          when "video_detail"
            video = resolve_target(::Video, id_key: :video_id, noun_fillers: VIDEO_NOUN_FILLERS)
            return needs_ref unless video.is_a?(::Video)

            confirmation(Pito::MessageBuilder::Sync::VideosConfirmation.call(
              nil, channel_ids: [], video_ids: [ video.id ], conversation:
            ))
          when "channel_detail"
            ch = resolve_target(::Channel, id_key: :channel_id, noun_fillers: CHANNEL_NOUN_FILLERS)
            return needs_ref unless ch.is_a?(::Channel)

            confirmation(Pito::MessageBuilder::Sync::ChannelConfirmation.call(
              ch.handle.presence || ch.title.to_s, channel_ids: [ ch.id ], with_items: [], conversation:
            ))
          when "game_detail"
            game = resolve_target(::Game, id_key: :game_id, noun_fillers: GAME_NOUN_FILLERS)
            return needs_ref unless game.is_a?(::Game)

            confirmation(Pito::MessageBuilder::Sync::GameConfirmation.call(game, conversation:))
          else
            needs_ref
          end
        end

        def confirmation(payload)
          Pito::Chat::Result::Ok.new(events: [ { kind: :confirmation, payload: payload } ])
        end

        # ── Noun-form predicates ─────────────────────────────────────────────────

        def channels_form?(raw)
          raw.match?(/(?<!-)\bchannels?\b/i)
        end

        def videos_form?(raw)
          raw.match?(/(?<!-)\b(?:vid|video)s?\b/i)
        end

        # ── sync videos [only <ids>] ─────────────────────────────────────────────

        def handle_videos(raw)
          video_ids = parse_video_ids(raw)

          if video_ids.any?
            # Ids win — sync exactly these videos, ignoring the shift+tab scope.
            payload = Pito::MessageBuilder::Sync::VideosConfirmation.call(
              nil, channel_ids: [], video_ids: video_ids, conversation:
            )
          else
            # No ids — obey the shift+tab channel scope.
            scope_label, channel_ids, error = resolve_scope
            return error if error

            payload = Pito::MessageBuilder::Sync::VideosConfirmation.call(
              scope_label, channel_ids: channel_ids, video_ids: [], conversation:
            )
          end
          Pito::Chat::Result::Ok.new(events: [ { kind: :confirmation, payload: payload } ])
        end

        # ── sync channels [with <items>] ─────────────────────────────────────────

        def handle_channels(raw)
          scope_label, channel_ids, error = resolve_scope
          return error if error

          with_items = parse_with_items(raw)

          if with_items.include?(:videos)
            payload = Pito::MessageBuilder::Sync::ChannelVideosConfirmation.call(
              scope_label, channel_ids: channel_ids, with_items: with_items, conversation:
            )
          else
            payload = Pito::MessageBuilder::Sync::ChannelConfirmation.call(
              scope_label, channel_ids: channel_ids, with_items: with_items, conversation:
            )
          end
          Pito::Chat::Result::Ok.new(events: [ { kind: :confirmation, payload: payload } ])
        end

        # ── Clause parsers ───────────────────────────────────────────────────────

        # Parses video ids from the raw input. Prefers `#id[,#id…]` (the canonical
        # ref form used across pito — `show vid #23`, `link #1 #2`); falls back to
        # the legacy `only <ids>` clause. Returns [] when neither is present.
        HASH_ID_RE = /#(\d+)/

        def parse_video_ids(raw)
          hashed = raw.to_s.scan(HASH_ID_RE).flatten.map(&:to_i).select(&:positive?).uniq
          return hashed if hashed.any?

          parse_only_ids(raw)
        end

        # Parses `only <id>[,<id>…]` → Array<Integer> of local video ids.
        # Returns [] when the clause is absent.
        ONLY_RE = /\bonly\b\s+([\d,\s]+)/i

        def parse_only_ids(raw)
          match = ONLY_RE.match(raw.to_s)
          return [] unless match

          match[1].split(/\s*,\s*/).filter_map { |token|
            int = Integer(token.strip, 10, exception: false)
            int if int&.positive?
          }
        end

        # Parses `with <item>[,<item>…]` using WITH_ITEMS_VOCAB.
        # Mirrors WithColumns: split on commas, map through vocabulary, uniq.
        # Returns [] when the clause is absent or all tokens are unknown.
        WITH_RE = /\bwith\b\s+(.+?)(?:\z)/i

        def parse_with_items(raw)
          match = WITH_RE.match(raw.to_s)
          return [] unless match

          match[1]
            .split(/\s*,\s*/)
            .filter_map { |token| WITH_ITEMS_VOCAB[token.strip.downcase] }
            .uniq
        end

        # ── Scope resolution ─────────────────────────────────────────────────────
        #
        # Returns [scope_label, channel_ids_array, nil] on success
        # or [nil, nil, Result::Ok(error event)] on unknown handle.
        # channel_ids is empty when scope is @all (all channels).
        def resolve_scope
          handle = resolved_channel_handle

          if handle.nil?
            # @all or blank → all channels
            return [ "all channels", [], nil ]
          end

          norm = normalized_handle(handle)
          ch   = ::Channel.find_by("LOWER(REPLACE(handle, '@', '')) = LOWER(?)", norm)

          if ch.nil?
            error_payload = Pito::MessageBuilder::Text.call(
              "pito.copy.channels.not_found",
              handle: handle
            )
            return [ nil, nil, Pito::Chat::Result::Ok.new(events: [
              { kind: :system, payload: error_payload }
            ]) ]
          end

          [ ch.handle.presence || handle, [ ch.id ], nil ]
        end

        # Returns the handle string for a specific channel, or nil for @all/blank.
        def resolved_channel_handle
          ch = channel.to_s.strip
          return nil if ch.blank? || ch.casecmp("@all").zero?

          ch
        end

        def normalized_handle(handle)
          handle.to_s.sub(/\A@+/, "")
        end

        # ── Fuzzy noun detection ──────────────────────────────────────────────────

        # Returns [canonical, correction_or_nil] using the :sync_targets vocab.
        # Only called when the exact regex forms (channels_form? / videos_form?)
        # both miss. Drops the verb token ("sync") before scanning.
        def detect_sync_noun_fuzzy(raw)
          vocab  = Pito::Grammar::Registry.vocabulary(:sync_targets)
          tokens = raw.to_s.downcase.split(/\s+/).drop(1)  # drop "sync"
          tokens.each do |token|
            next if token.start_with?("#", "@", "-")  # skip refs, handles, flags
            fuzzy = vocab.resolve_fuzzy(token)
            return [ fuzzy, { original: token, canonical: fuzzy } ] if fuzzy
          end
          [ nil, nil ]
        end

        # Prepends a short note event when a fuzzy correction fired.
        # No-op when correction is nil, result is not Ok, or events are empty.
        def prepend_typo_note(result, correction)
          return result unless correction && result.is_a?(Pito::Chat::Result::Ok) && result.events.any?

          note_text  = Pito::Copy.render(
            "pito.copy.grammar.typo_correction",
            original: correction[:original], canonical: correction[:canonical]
          )
          Pito::Chat::Result::Ok.new(
            events: [ { kind: :system, payload: { "text" => note_text } } ] + result.events
          )
        end

        # ── Error helpers ─────────────────────────────────────────────────────────

        def needs_ref
          Pito::Chat::Result::Error.new(
            message_key:  "pito.chat.sync.needs_ref",
            message_args: {}
          )
        end
      end
    end
  end
end
