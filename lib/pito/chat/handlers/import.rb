# frozen_string_literal: true

# Handler for the `import` chat tool.
#
# Two sub-forms:
#
#   import [game[s]] [title] — open the IGDB import sidebar (fast-path). Games are
#                              the only importable thing, so the noun is optional:
#                              `import tekken` == `import game tekken` (#11). The
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
# Bare `import` (no title) → opens the IGDB sidebar empty.
module Pito
  module Chat
    module Handlers
      class Import < Pito::Chat::Handler
        self.tool = :import
        self.description_key = "pito.chat.import.descriptions.import"

        # `for @handle` override clause: captures the handle after `for`.
        FOR_HANDLE_RE = /\bfor\s+(@\S+)/i

        def call
          raw = message.raw.to_s
          noun, correction = detect_import_noun(raw)

          # #11: games are the only importable thing, so anything that isn't the
          # `import videos` sync alias — `import game <title>`, `import <title>`,
          # bare `import` — is an IGDB game import.
          result =
            if noun == "videos"
              handle_import_videos(raw)
            else
              handle_import_game(raw, noun_token: correction&.dig(:original))
            end

          prepend_typo_note(result, correction)
        end

        private

        # Detects the import noun ("game" / "videos") from the raw input.
        # Returns [canonical_noun, correction_or_nil].
        # correction is { original:, canonical: } when a fuzzy match was used.
        def detect_import_noun(raw)
          tokens = raw.to_s.downcase.split(/\s+/).drop(1)  # drop the tool word "import"

          # Exact "game"/"games" wins FIRST — game branch fires even when a video
          # noun is also present ("import game videos" → game branch, prefill
          # "videos"). (Checking the video regex first wrongly stole that case.)
          vocab = Pito::Grammar::Registry.vocabulary(:import_nouns)
          tokens.each do |token|
            next if token.start_with?("#", "@", "-")  # skip refs, handles, flags
            canon = vocab.resolve(token)
            return [ canon, nil ] if canon
          end

          # Videos form (raw regex; not in IMPORT_NOUNS) — only when no exact game.
          return [ "videos", nil ] if raw.match?(/\b(?:vid|video)s?\b/i)

          # Fuzzy fallback on IMPORT_NOUNS only (after exact game + video miss).
          tokens.each do |token|
            next if token.start_with?("#", "@", "-")  # skip refs, handles, flags
            fuzzy = vocab.resolve_fuzzy(token)
            return [ fuzzy, { original: token, canonical: fuzzy } ] if fuzzy
          end

          [ nil, nil ]
        end

        # Open the IGDB import sidebar, with an optional prefill title.
        # Mirrors Pito::Slash::Handlers::Games#open_import_sidebar.
        # noun_token is the raw word that was fuzzy-resolved to "game" — it is
        # stripped from the title so the prefill contains only the game name.
        def handle_import_game(raw, noun_token: nil)
          title = parse_import_game_title(raw, noun_token:)
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

        # Extract the title from `import [game[s]] [title]` (#11 — the noun is
        # optional). Strips the leading `import` tool, then an optional `game[s]`
        # noun (or the fuzzy-matched noun_token); whatever remains is the title.
        def parse_import_game_title(raw, noun_token: nil)
          rest = raw.to_s.strip.sub(/\Aimport\b\s*/i, "")
          rest =
            if noun_token
              rest.sub(/\A#{Regexp.escape(noun_token)}\b\s*/i, "")
            else
              rest.sub(/\Agames?\b\s*/i, "")
            end
          rest.strip
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
