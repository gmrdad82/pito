# frozen_string_literal: true

module Pito
  module FollowUp
    module Handlers
      # Follow-up handler for the `/resume <name>` not-found message
      # (reply_target: "resume_missing").
      #
      # The message's PRIMARY affordances are clicky prefill+submit tokens
      # (`/new <name>` + `/resume <title>`). This handler covers the keyboard /
      # `#<handle>` path (shift+r): replying `new` / `create` creates the named
      # conversation (the name is stashed in the message payload as `resume_name`).
      #
      # Browser navigation can't happen from a follow-up broadcast, so the reply
      # CREATES the conversation and confirms; the user opens it via the resume
      # sidebar or `/resume <name>` (which now matches).
      #
      # NAMESPACE: use `::Conversation` for the model.
      class ResumeMissing < Pito::FollowUp::Handler
        self.target "resume_missing"

        def call(event:, rest:, conversation:, **)
          action, _args = parse_rest(rest)
          # tools.yml decides availability (the matrix), not a hardcoded list.
          return undeclared_action(action) unless declared?(action)

          name = event.payload.with_indifferent_access[:resume_name].to_s.strip
          return invalid_action(action) if name.blank?

          new_conversation = ::Conversation.create!
          ::Conversation::Rename.call(conversation: new_conversation, title: name)

          Pito::FollowUp::Result::Append.new(events: [
            { kind: :system, payload: Pito::MessageBuilder::Text.call(
              "pito.copy.resume_missing.created", name: name
            ) }
          ])
        end

        private

        def invalid_action(action)
          Pito::FollowUp::Result::Error.new(
            message_key:  "pito.follow_up.resume_missing.errors.invalid_action",
            message_args: { action: action }
          )
        end
      end
    end
  end
end
