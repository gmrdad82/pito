# frozen_string_literal: true

module Pito
  module MessageBuilder
    module Conversation
      # Built when `/resume <name>` finds no conversation by that name.
      #
      # Renders a repliable message offering to CREATE the named conversation, and
      # — when any exist — a LIST of similarly-named conversations (typo recovery).
      # Every option is a CLICKY cyan-shimmer prefill+submit token
      # (Pito::Shimmer::TokenComponent, submit: true): clicking fills the chatbox
      # with the full slash command and presses Enter, so:
      #   create  → `/new <name>`
      #   each suggestion → `/resume <that title>`
      # No follow-up-navigation hack — the prefilled command runs the normal
      # controller path. The message is stamped follow-up-able so shift+r can
      # surface the same set as premade replies.
      #
      # NAMESPACE: `Conversation` here is Pito::MessageBuilder::Conversation; the
      # similar records are passed in (already resolved by ::Conversation).
      module ResumeMissing
        extend Pito::MessageBuilder::Helpers
        module_function

        # @param name         [String]            the requested (missing) conversation name.
        # @param similar      [Array<::Conversation>] up to 5 fuzzy-similar conversations ([] = none).
        # @param conversation [::Conversation]     the current conversation (for the reply handle).
        # @return [Hash] follow-up-able html payload (target: "resume_missing").
        def call(name:, similar:, conversation:)
          h     = ActionController::Base.helpers
          lines = []

          # create_prompt: "no conversation named <name> — create it?" (name shimmered)
          lines << h.tag.div(
            Pito::Copy.render_html("pito.copy.resume_missing.create_prompt", { name: name }, shimmer: [ :name ])
          )
          lines << h.tag.div(prefill_token(h, "/new #{name}"))

          if similar.any?
            lines << h.tag.div(
              Pito::Copy.render("pito.copy.resume_missing.suggestions_intro"),
              class: "text-fg-dim"
            )
            similar.each { |c| lines << h.tag.div(prefill_token(h, "/resume #{c.title}")) }
          end

          # Stash the requested name so the follow-up handler (and shift+r `#<h> new`)
          # can create it without re-typing.
          payload = html_payload(body: h.safe_join(lines), resume_name: name)
          Pito::FollowUp.make_followupable!(payload, target: "resume_missing", conversation:)
          payload
        end

        # A clicky cyan-shimmer token that prefills the chatbox with `command` and
        # auto-submits (Enter) on click.
        def prefill_token(helpers, command)
          helpers.tag.span(
            command,
            class: Pito::Shimmer::TokenComponent.css_class(command, extra: "whitespace-nowrap"),
            data:  Pito::Shimmer::TokenComponent.prefill_data(command, submit: true)
          )
        end
        private_class_method :prefill_token
      end
    end
  end
end
