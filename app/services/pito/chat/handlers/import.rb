# frozen_string_literal: true

# Handler for the `import` chat verb.
#
# Two sub-forms:
#
#   import game[s] [title]  — the IGDB import sidebar fast-path. In practice the
#                              ChatController intercepts this before it reaches
#                              this handler, but we fall through gracefully with a
#                              usage hint.
#   import videos           — channel-scoped YouTube newer-only import. Emits a
#                              `:confirmation` event; the executor enqueues
#                              ChatImportVideosJob on confirm. Channel scope from
#                              `self.channel` (same resolution as List handler).
#
# Bare `import` with no noun → usage hint.
module Pito
  module Chat
    module Handlers
      class Import < Pito::Chat::Handler
        self.verb = :import
        self.description_key = "pito.chat.import.descriptions.import"

        def call
          raw = message.raw.to_s

          if raw.match?(/\bvideos?\b/i)
            handle_import_videos
          else
            Pito::Chat::Result::Error.new(
              message_key:  "pito.chat.import.usage_hint",
              message_args: {}
            )
          end
        end

        private

        def handle_import_videos
          scope_label, channel_ids, error = resolve_scope
          return error if error

          payload = Pito::MessageBuilder::Sync::ImportVideosConfirmation.call(
            scope_label, channel_ids: channel_ids, conversation:
          )
          Pito::Chat::Result::Ok.new(events: [ { kind: :confirmation, payload: payload } ])
        end

        # Mirrors List / Sync handlers: @all/blank → all channels, @handle → one.
        def resolve_scope
          handle = resolved_channel_handle

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
