# frozen_string_literal: true

module Pito
  module Grammar
    module Specs
      # ── Private helpers ──────────────────────────────────────────────────────

      def self.chat_shared_slots
        [
          Slot.new(name: :status,   kind: :enum, source: :release_status, optional: true),
          Slot.new(name: :genre,    kind: :enum, source: :genres,    repeatable: true, optional: true),
          Slot.new(name: :platform, kind: :enum, source: :platforms,  optional: true, introducer: :for)
        ]
      end
      private_class_method :chat_shared_slots

      # ── Public API ───────────────────────────────────────────────────────────

      def self.all
        [
          # Handler-less slash command specs (login/logout/connect have no handler class)
          # `/games import [title]` — slash spec for the IGDB import sidebar.
          # The `:games_subcommands` vocab has a single canonical entry "import"
          # so the palette shows "/games import" with a description.  The title
          # arg is free-form (any string); it is parsed directly in the handler.
          Spec.new(
            namespace:       :slash,
            name:            :games,
            slots:           [
              Slot.new(name: :subcommand, kind: :enum, source: :games_subcommands, optional: true),
              Slot.new(name: :title, kind: :free, optional: true)
            ],
            auth:            :authenticated_only,
            description_key: "pito.grammar.slash.games"
          ),

          # Handler-less slash command specs (login/logout/connect have no handler class)
          Spec.new(
            namespace:       :slash,
            name:            :login,
            slots:           [ Slot.new(name: :code, kind: :free) ],
            auth:            :unauthenticated_only,
            description_key: "pito.grammar.slash.login"
          ),
          Spec.new(
            namespace:       :slash,
            name:            :logout,
            slots:           [],
            auth:            :authenticated_only,
            description_key: "pito.grammar.slash.logout"
          ),
          Spec.new(
            namespace:       :slash,
            name:            :connect,
            slots:           [],
            auth:            :authenticated_only,
            description_key: "pito.grammar.slash.connect"
          ),
          Spec.new(
            namespace:       :slash,
            name:            :new,
            slots:           [],
            auth:            :authenticated_only,
            description_key: "pito.grammar.slash.new"
          ),
          Spec.new(
            namespace:       :slash,
            name:            :resume,
            slots:           [],
            auth:            :authenticated_only,
            description_key: "pito.grammar.slash.resume"
          ),

          # Task k — chat command specs
          # `list`/`ls` takes a single noun (channels/videos/games). The enum slot
          # drives the suggestion ghost (`list ` → channels) and recognises the
          # noun; the handler reads message.raw to route, so this is suggestions-only.
          Spec.new(
            namespace:       :chat,
            name:            :list,
            aliases:         [ :ls ],
            slots:           [ Slot.new(name: :noun, kind: :enum, source: :nouns, optional: true) ],
            description_key: "pito.grammar.chat.list"
          ),
          # `show` / `delete` take a single game reference (ID or title). The
          # `:title` enum slot with source `:game_titles` enables dynamic ghost
          # completion (typing "show game li" ghosts a matching library title).
          # The noun words `game`/`games` are FILLERS, so the resolver skips them.
          # Handlers do their own body-token extraction so the slot kind here only
          # affects the suggestions engine — no handler change needed.
          Spec.new(
            namespace:       :chat,
            name:            :show,
            slots:           [ Slot.new(name: :title, kind: :enum, source: :game_titles, optional: true) ],
            description_key: "pito.grammar.chat.show"
          ),
          Spec.new(
            namespace:       :chat,
            name:            :import,
            slots:           [
              Slot.new(name: :noun,  kind: :enum, source: :import_nouns, optional: false),
              Slot.new(name: :title, kind: :free,  optional: true)
            ],
            description_key: "pito.grammar.chat.import"
          ),
          # `sync` — noun-discriminated at the handler level from message.raw:
          #   sync game <ref>  /  sync video <ref>  /  sync videos  /
          #   sync channel  /  sync channel with videos
          # The slot is free/optional so any noun phrase is accepted.
          Spec.new(
            namespace:       :chat,
            name:            :sync,
            slots:           [ Slot.new(name: :target, kind: :free, optional: true) ],
            description_key: "pito.grammar.chat.sync"
          ),
          Spec.new(
            namespace:       :chat,
            name:            :footage,
            slots:           [ Slot.new(name: :title, kind: :enum, source: :game_titles, optional: true) ],
            description_key: "pito.grammar.chat.footage"
          ),
          Spec.new(
            namespace:       :chat,
            name:            :delete,
            aliases:         [ :rm ],
            slots:           [ Slot.new(name: :title, kind: :enum, source: :game_titles, optional: true) ],
            description_key: "pito.grammar.chat.delete"
          ),
          Spec.new(
            namespace:       :chat,
            name:            :reindex,
            slots:           [ Slot.new(name: :title, kind: :enum, source: :game_titles, optional: true) ],
            description_key: "pito.grammar.chat.reindex"
          ),
          Spec.new(
            namespace:       :chat,
            name:            :publish,
            slots:           [ Slot.new(name: :title, kind: :free, optional: true) ],
            description_key: "pito.grammar.chat.publish"
          ),
          Spec.new(
            namespace:       :chat,
            name:            :unlist,
            slots:           [ Slot.new(name: :title, kind: :free, optional: true) ],
            description_key: "pito.grammar.chat.unlist"
          ),
          Spec.new(
            namespace:       :chat,
            name:            :schedule,
            slots:           [
              Slot.new(name: :title, kind: :free, optional: true),
              Slot.new(name: :when,  kind: :free, optional: true)
            ],
            description_key: "pito.grammar.chat.schedule"
          ),
          Spec.new(
            namespace:       :chat,
            name:            :find,
            slots:           chat_shared_slots,
            description_key: "pito.grammar.chat.find"
          ),
          # `link` / `unlink` take a free body — the handler splits on ` to `
          # to extract the game and video refs.
          Spec.new(
            namespace:       :chat,
            name:            :link,
            slots:           [ Slot.new(name: :title, kind: :free, optional: true) ],
            description_key: "pito.grammar.chat.link"
          ),
          Spec.new(
            namespace:       :chat,
            name:            :unlink,
            slots:           [ Slot.new(name: :title, kind: :free, optional: true) ],
            description_key: "pito.grammar.chat.unlink"
          ),
          # `help` — no slots; displays all follow-up targets grouped by entity.
          Spec.new(
            namespace:       :chat,
            name:            :help,
            slots:           [],
            description_key: "pito.grammar.chat.help"
          )

        ]
      end

      def self.register_all!(registry)
        all.each { |spec| registry.register_spec(spec) }
      end
    end
  end
end
