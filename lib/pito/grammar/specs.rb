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

      def self.hashtag_metric_slots
        [
          Slot.new(name: :metric, kind: :enum, source: :metrics, repeatable: true)
        ]
      end
      private_class_method :hashtag_metric_slots

      # ── Public API ───────────────────────────────────────────────────────────

      def self.all
        [
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
          Spec.new(
            namespace:       :chat,
            name:            :list,
            aliases:         [ :ls ],
            slots:           chat_shared_slots,
            description_key: "pito.grammar.chat.list"
          ),
          # `show` / `delete` take a single game reference (ID or title). The
          # `:title` free slot slurps the remaining tokens (the noun word
          # `game`/`games` is dropped as a FILLER), e.g. `show game lies of p`.
          Spec.new(
            namespace:       :chat,
            name:            :show,
            slots:           [ Slot.new(name: :title, kind: :free, optional: true) ],
            description_key: "pito.grammar.chat.show"
          ),
          Spec.new(
            namespace:       :chat,
            name:            :delete,
            aliases:         [ :rm ],
            slots:           [ Slot.new(name: :title, kind: :free, optional: true) ],
            description_key: "pito.grammar.chat.delete"
          ),
          Spec.new(
            namespace:       :chat,
            name:            :find,
            slots:           chat_shared_slots,
            description_key: "pito.grammar.chat.find"
          ),

          # Task l — hashtag command specs
          Spec.new(
            namespace:       :hashtag,
            name:            :add,
            aliases:         [ :include ],
            slots:           hashtag_metric_slots,
            description_key: "pito.grammar.hashtag.add"
          ),
          Spec.new(
            namespace:       :hashtag,
            name:            :remove,
            aliases:         [ :drop, :delete ],
            slots:           hashtag_metric_slots,
            description_key: "pito.grammar.hashtag.remove"
          )

        ]
      end

      def self.register_all!(registry)
        all.each { |spec| registry.register_spec(spec) }
      end
    end
  end
end
