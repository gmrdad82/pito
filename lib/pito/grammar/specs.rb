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
            aliases:         [ :authenticate ],
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
            slots:           [ Slot.new(name: :name, kind: :free, optional: true) ],
            auth:            :authenticated_only,
            description_key: "pito.grammar.slash.new"
          ),
          Spec.new(
            namespace:       :slash,
            name:            :resume,
            slots:           [ Slot.new(name: :name, kind: :free, optional: true) ],
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
          # `show` takes a single numeric id (`show game <id>` / `show video <id>`).
          # Title lookup is disabled (id_only_resolution! in the handler). The slot
          # is free/optional — the suggestions engine gets no title ghost for `show`.
          # The noun words `game`/`games`/`video`/`videos` are FILLERS handled by the
          # resolver; the handler reads message.raw to route.
          Spec.new(
            namespace:       :chat,
            name:            :show,
            slots:           [ Slot.new(name: :id, kind: :free, optional: true) ],
            description_key: "pito.grammar.chat.show"
          ),
          # `analyze` (aliases `analytics`/`stats`) — interval-aware YouTube
          # analytics for a channel/vid/game scope. Mirrors `list`: the enum slot
          # drives the suggestion ghost (`analyze ` → channels) and recognises the
          # noun; the handler reads message.raw to route the entity + ids/handles,
          # the shift+tab channel scope, and the shift+space period. `stats` is a
          # friendlier alias and is NOT the internal `Pito::Stats` layer.
          Spec.new(
            namespace:       :chat,
            name:            :analyze,
            aliases:         [ :analytics, :stats ],
            slots:           [ Slot.new(name: :noun, kind: :enum, source: :nouns, optional: true) ],
            description_key: "pito.grammar.chat.analyze"
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
          # The enum slot drives the suggestion ghost (`sync ` → channels/videos)
          # and recognises the noun; the handler still reads message.raw to route,
          # so this is suggestions-only — any noun phrase is still accepted.
          Spec.new(
            namespace:       :chat,
            name:            :sync,
            slots:           [ Slot.new(name: :target, kind: :enum, source: :sync_targets, optional: true) ],
            description_key: "pito.grammar.chat.sync"
          ),
          Spec.new(
            namespace:       :chat,
            name:            :footage,
            slots:           [ Slot.new(name: :title, kind: :enum, source: :game_titles, optional: true) ],
            description_key: "pito.grammar.chat.footage"
          ),
          # `price set <id> <amount>` / `price unset <id>` — a leading enum slot
          # surfaces the `set`/`unset` subcommand as a TAB-completable ghost (`price `
          # → "set"); the trailing free slot absorbs the id + amount. Suggestions-only:
          # the handler reads the subcommand, id, and amount from message.raw.
          Spec.new(
            namespace:       :chat,
            name:            :price,
            slots:           [
              Slot.new(name: :subcommand, kind: :enum, source: :price_subcommands, optional: true),
              Slot.new(name: :title,      kind: :free, optional: true)
            ],
            description_key: "pito.grammar.chat.price"
          ),
          Spec.new(
            namespace:       :chat,
            name:            :delete,
            aliases:         [ :rm, :del ],
            slots:           [ Slot.new(name: :title, kind: :enum, source: :game_titles, optional: true) ],
            description_key: "pito.grammar.chat.delete"
          ),
          Spec.new(
            namespace:       :chat,
            name:            :reindex,
            slots:           [ Slot.new(name: :title, kind: :enum, source: :game_titles, optional: true) ],
            description_key: "pito.grammar.chat.reindex"
          ),
          # `platform` ADDS or REMOVES a game's platform — `platform set <id>
          # <name>` / `platform unset <id> <name>` (bare `platform <id> <name>`
          # still adds). The enum subcommand slot ghosts set/unset (like price); the
          # trailing free slot absorbs the id + name. Suggestions-only: the handler
          # reads the subcommand, id, and name from message.raw.
          Spec.new(
            namespace:       :chat,
            name:            :platform,
            slots:           [
              Slot.new(name: :subcommand, kind: :enum, source: :platform_subcommands, optional: true),
              Slot.new(name: :title,      kind: :free, optional: true)
            ],
            description_key: "pito.grammar.chat.platform"
          ),
          Spec.new(
            namespace:       :chat,
            name:            :publish,
            aliases:         [ :pub ],
            slots:           [ Slot.new(name: :title, kind: :free, optional: true) ],
            description_key: "pito.grammar.chat.publish"
          ),
          Spec.new(
            namespace:       :chat,
            name:            :unlist,
            slots:           [ Slot.new(name: :title, kind: :free, optional: true) ],
            description_key: "pito.grammar.chat.unlist"
          ),
          # `schedule <id> <when|slate>` — the leading free slot absorbs the id +
          # explicit <when> phrase (parsed by Pito::Schedule::TimeParser at the
          # handler); the trailing enum slot surfaces `slate` (the next-open-slot
          # keyword) as a TAB-completable suggestion alongside an explicit date.
          Spec.new(
            namespace:       :chat,
            name:            :schedule,
            slots:           [
              Slot.new(name: :title, kind: :free, optional: true),
              Slot.new(name: :slate, kind: :enum, source: :schedule_whens, optional: true)
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
          ),

          # `shinies` — achievement track + obtained badges for a game, vid, or channel.
          # A single free slot so the ghost shows up after "shinies "; the handler
          # reads the noun (channel/video/game) + ref from message.raw directly.
          Spec.new(
            namespace:       :chat,
            name:            :shinies,
            slots:           [ Slot.new(name: :target, kind: :free, optional: true) ],
            description_key: "pito.grammar.chat.shinies"
          ),

          # `greet` / `farewell` — conversational hellos and goodbyes. Recognised
          # by a whole-input phrase match in Pito::Chat::Parser (single OR multi-word,
          # case-insensitive, punctuation-tolerant — "Hi", "good bye", "hasta luego"),
          # not by a first-word verb alias. These specs exist for handler↔spec parity
          # + help text; they take no args.
          Spec.new(
            namespace:       :chat,
            name:            :greet,
            slots:           [],
            description_key: "pito.grammar.chat.greet"
          ),
          Spec.new(
            namespace:       :chat,
            name:            :farewell,
            slots:           [],
            description_key: "pito.grammar.chat.farewell"
          )

        ]
      end

      def self.register_all!(registry)
        all.each { |spec| registry.register_spec(spec) }
      end
    end
  end
end
