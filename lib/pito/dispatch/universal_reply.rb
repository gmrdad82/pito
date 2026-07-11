# frozen_string_literal: true

module Pito
  module Dispatch
    # Per-verb gate for the universal share / unshare|revoke reply actions.
    #
    # The top-level `universal_reply:` block in config/pito/verbs.yml declares the
    # universal actions themselves; a VERB opts its messages out of them with
    # `universal_reply: false` on its own verbs.yml entry. The Finalizer and the
    # Broadcaster stamp each persisted message with its `origin_verb` (derived
    # here) and withhold the universal-only reply handle for opted-out verbs; the
    # suggestions palette and the follow-up dispatch consult the same stamp so a
    # typed `#handle share` is refused consistently with what the palette offers.
    module UniversalReply
      module_function

      # True when `verb` declares `universal_reply: false` on its verbs.yml entry.
      def opted_out?(verb)
        return false if verb.blank?

        Pito::Dispatch::Config.verb(verb.to_sym)[:universal_reply] == false
      rescue KeyError
        false
      end

      # True when universal actions may attach to `event`. Events without an
      # `origin_verb` stamp (pre-existing rows, chrome emitted outside dispatch)
      # default to allowed.
      def allowed_for?(event)
        !opted_out?(event&.payload&.[]("origin_verb"))
      end

      # The canonical verb that produced `turn`'s messages, or nil when it cannot
      # be determined (auth chrome, unparseable input). Slash and hashtag turns
      # resolve their leading token through the Matrix alias index; chat turns run
      # the real chat parse so aliases and fillers resolve exactly like dispatch.
      def origin_verb(turn)
        input = turn&.input_text.to_s
        return nil if input.blank?

        if turn.hashtag?
          action = input.sub(/\A#\S+\s*/, "").split(/\s+/).first
          Pito::Dispatch::Matrix.verb_for(action.to_s.downcase)
        elsif turn.slash?
          Pito::Dispatch::Matrix.verb_for(input.delete_prefix("/").split(/\s+/).first.to_s.downcase)
        else
          chat_verb(input, turn.conversation)
        end
      end

      def chat_verb(input, conversation)
        tokens  = Pito::Lex::KeywordSanitizer.call(Pito::Lex::Lexer.call(input))
        message = Pito::Chat::Parser.call(tokens, raw: input, conversation:)
        message.respond_to?(:verb) ? message.verb&.to_s : nil
      rescue StandardError
        nil
      end
    end
  end
end
