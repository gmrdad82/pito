# frozen_string_literal: true

# Handler for the `sync` chat verb — exactly two target forms.
#
#   sync videos [only <id>,<id>,…]
#     Sync YouTube data for videos scoped by the shift+tab channel:
#       @all / blank → all channels; @handle → that channel.
#     The optional `only <ids>` clause restricts the sync to the given local
#     video ids (comma-separated plain integers).
#
#   sync channels [with <item>[,<item>…]]
#     Sync channel fields + stats scoped by the shift+tab channel:
#       @all → all channels; @handle → one channel.
#     The optional `with <items>` clause is a generic comma-list of sync
#     targets — today only `videos` is acted upon, but `analytics` and
#     others parse without error (built to extend).
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
          "vid"       => :videos,
          "vids"      => :videos,
          "video"     => :videos,
          "videos"    => :videos,
          "analytic"  => :analytics,
          "analytics" => :analytics
        }.freeze

        def call
          raw = message.raw.to_s

          if channels_form?(raw)
            handle_channels(raw)
          elsif videos_form?(raw)
            handle_videos(raw)
          else
            needs_ref
          end
        end

        private

        # ── Noun-form predicates ─────────────────────────────────────────────────

        def channels_form?(raw)
          raw.match?(/(?<!-)\bchannels?\b/i)
        end

        def videos_form?(raw)
          raw.match?(/(?<!-)\b(?:vid|video)s?\b/i)
        end

        # ── sync videos [only <ids>] ─────────────────────────────────────────────

        def handle_videos(raw)
          scope_label, channel_ids, error = resolve_scope
          return error if error

          video_ids = parse_only_ids(raw)

          payload = Pito::MessageBuilder::Sync::VideosConfirmation.call(
            scope_label, channel_ids: channel_ids, video_ids: video_ids, conversation:
          )
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
