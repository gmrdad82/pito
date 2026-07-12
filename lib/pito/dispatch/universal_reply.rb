# frozen_string_literal: true

module Pito
  module Dispatch
    # Per-tool gate for the universal share / unshare|revoke reply actions.
    #
    # The top-level `universal_reply:` block in config/pito/tools.yml declares the
    # universal actions themselves; a TOOL opts its messages out of them with
    # `universal_reply: false` on its own tools.yml entry. The Finalizer and the
    # Broadcaster stamp each persisted message's `origin_verb` payload key (value
    # derived by `origin_tool` here) and withhold the universal-only reply handle
    # for opted-out tools; the suggestions palette and the follow-up dispatch
    # consult the same stamp so a typed `#handle share` is refused consistently
    # with what the palette offers.
    module UniversalReply
      module_function

      # True when `tool` declares `universal_reply: false` on its tools.yml entry.
      def opted_out?(tool)
        return false if tool.blank?

        Pito::Dispatch::Config.tool(tool.to_sym)[:universal_reply] == false
      rescue KeyError
        false
      end

      # True when universal actions may attach to `event`. Events without an
      # `origin_verb` stamp (pre-existing rows, chrome emitted outside dispatch)
      # default to allowed.
      def allowed_for?(event)
        !opted_out?(event&.payload&.[]("origin_tool") || event&.payload&.[]("origin_verb"))
      end

      # The canonical tool that produced `turn`'s messages, or nil when it cannot
      # be determined (auth chrome, unparseable input). Slash and hashtag turns
      # resolve their leading token through the Matrix alias index; chat turns run
      # the real chat parse so aliases and fillers resolve exactly like dispatch.
      def origin_tool(turn)
        input = turn&.input_text.to_s
        return nil if input.blank?

        if turn.hashtag?
          action = input.sub(/\A#\S+\s*/, "").split(/\s+/).first
          Pito::Dispatch::Matrix.tool_for(action.to_s.downcase)
        elsif turn.slash?
          Pito::Dispatch::Matrix.tool_for(input.delete_prefix("/").split(/\s+/).first.to_s.downcase)
        else
          chat_tool(input, turn.conversation)
        end
      end

      def chat_tool(input, conversation)
        tokens  = Pito::Lex::KeywordSanitizer.call(Pito::Lex::Lexer.call(input))
        message = Pito::Chat::Parser.call(tokens, raw: input, conversation:)
        message.respond_to?(:tool) ? message.tool&.to_s : nil
      rescue StandardError
        nil
      end
    end
  end
end
