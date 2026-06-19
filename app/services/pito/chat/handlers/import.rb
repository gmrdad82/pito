# frozen_string_literal: true

# Handler for the `import` chat verb.
#
# Two sub-forms:
#
#   import game[s] [title]  — open the IGDB import sidebar (fast-path). The
#                              ChatController intercepts this before the async
#                              pipeline; this handler handles the job-path
#                              fallback by returning the same sidebar_open event
#                              that the slash /games import handler uses.
#   import videos [for @handle]
#                           — ALIAS for `sync videos` (whole-channel sync). Emits
#                              the same `:confirmation` event `sync videos` does,
#                              so the executor enqueues SyncVideosJob on confirm.
#                              Channel scope: shift+tab @all/blank → all channels;
#                              @handle → that channel. The optional `for @handle`
#                              clause in the raw text OVERRIDES the shift+tab scope.
#
# Bare `import` with no noun → usage hint.
module Pito
  module Chat
    module Handlers
      class Import < Pito::Chat::Handler
        self.verb = :import
        self.description_key = "pito.chat.import.descriptions.import"

        # `for @handle` override clause: captures the handle after `for`.
        FOR_HANDLE_RE = /\bfor\s+(@\S+)/i

        def call
          raw = message.raw.to_s

          if raw.match?(/\bgames?\b/i)
            handle_import_game(raw)
          elsif raw.match?(/\bvideos?\b/i)
            handle_import_videos(raw)
          else
            Pito::Chat::Result::Error.new(
              message_key:  "pito.chat.import.usage_hint",
              message_args: {}
            )
          end
        end

        private

        # Open the IGDB import sidebar, with an optional prefill title.
        # Mirrors Pito::Slash::Handlers::Games#open_import_sidebar.
        def handle_import_game(raw)
          title = parse_import_game_title(raw)
          Pito::Chat::Result::Ok.new(events: [
            {
              kind:    :system,
              payload: {
                sidebar_open: "games_import",
                prefill:      title,
                text:         I18n.t("pito.slash.games.import.opening")
              }
            }
          ])
        end

        # Extract the title from `import game[s] [title]`.
        # Strips leading `import` + optional `game`/`games` to get the rest.
        def parse_import_game_title(raw)
          raw.to_s.strip.sub(/\Aimport\s+games?\s*/i, "").strip
        end

        # `import videos` is a true alias for `sync videos` (whole-channel sync):
        # it builds the SAME confirmation `sync videos` builds, so confirming it
        # routes through `confirm_sync_videos` in the executor.
        def handle_import_videos(raw)
          scope_label, channel_ids, error = resolve_scope(raw)
          return error if error

          payload = Pito::MessageBuilder::Sync::VideosConfirmation.call(
            scope_label, channel_ids: channel_ids, conversation:
          )
          Pito::Chat::Result::Ok.new(events: [ { kind: :confirmation, payload: payload } ])
        end

        # Resolves channel scope for `import videos`.
        #
        # Priority:
        #   1. `for @handle` clause in raw text → that channel (overrides shift+tab)
        #   2. shift+tab channel filter        → specific channel or all
        #
        # Returns [scope_label, channel_ids, nil] on success,
        #         [nil, nil, Result::Ok(error event)] on unknown handle.
        def resolve_scope(raw)
          handle = for_handle_override(raw) || resolved_channel_handle

          if handle.nil?
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

        # Returns the handle from a `for @handle` clause in raw, or nil.
        def for_handle_override(raw)
          m = FOR_HANDLE_RE.match(raw.to_s)
          m ? m[1] : nil
        end

        def resolved_channel_handle
          ch = channel.to_s.strip
          return nil if ch.blank? || ch.casecmp("@all").zero?

          ch
        end

        def normalized_handle(handle)
          handle.to_s.sub(/\A@+/, "")
        end
      end
    end
  end
end
