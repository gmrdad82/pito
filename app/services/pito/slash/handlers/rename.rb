# frozen_string_literal: true

module Pito
  module Slash
    module Handlers
      # Handler for `/rename <new title>` — renames the CURRENT conversation without
      # opening the /resume sidebar. Reuses Conversation::Rename (the same service
      # the sidebar edit uses), so the title update + the chatbox-name and
      # global-sidebar-row broadcasts are identical. The new name appears in the
      # chatbox (the purple name shows unless it's the default Unnamed).
      #
      #   /rename My Strategy Channel   → renames + confirms
      #   /rename                        → usage hint (no blank rename)
      #   /rename --help                 → man-style usage
      #
      # authenticated_only — renaming is an owner action; it also keeps /rename out
      # of the pre-login palette.
      class Rename < Pito::Slash::Handler
        self.verb            = :rename
        self.description_key = "pito.slash.rename.descriptions.rename"

        grammar do
          free :title, optional: true
          auth :authenticated_only
          description_key "pito.grammar.slash.rename"
        end

        def call
          return show_help if help?

          title = new_title
          return needs_title if title.blank?

          ::Conversation::Rename.call(conversation:, title:)

          Pito::Slash::Result::Ok.new(events: [
            { kind: :system, payload: Pito::MessageBuilder::Text.call("pito.copy.conversations.renamed", title:) }
          ])
        end

        private

        # The new title — everything after `/rename`, trimmed. Preserves spaces.
        def new_title
          invocation.raw.to_s.strip.sub(%r{\A/rename\b\s*}i, "").strip
        end

        def needs_title
          Pito::Slash::Result::Ok.new(events: [
            { kind: :system, payload: { text: I18n.t("pito.slash.rename.needs_title") } }
          ])
        end

        def show_help
          body = Pito::MessageBuilder::ManPage.render(
            usage:  I18n.t("pito.slash.rename.help.usage"),
            groups: [
              [ "Arguments:", [ [ "<new title>", I18n.t("pito.slash.rename.help.title_desc") ] ] ],
              [ "Options:",   [ [ "--help", "Print this help message" ] ] ]
            ]
          )
          Pito::Slash::Result::Ok.new(events: [
            { kind: :system, payload: { "html" => true, "body" => body } }
          ])
        end
      end
    end
  end
end
