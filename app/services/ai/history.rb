# frozen_string_literal: true

module Ai
  # Projects a conversation's recent scrollback into the wire `messages` array —
  # mixed-origin first-class: the model sees grammar-verb output next to its own
  # earlier answers, so `list vids` followed by `ai which of these …` just works.
  #
  #   echo events                          → user turns (the typed input)
  #   :ai events                           → assistant turns (their blocks,
  #                                          projected to text)
  #   :system/:enhanced (+ follow-ups,
  #   :error)                              → assistant turns via Mcp::EventText
  #                                          (the same projection MCP clients read)
  #   thinking / confirmation / theme_diff → skipped (transient chrome)
  #
  # Consecutive same-role messages are coalesced (Anthropic's alternation rule;
  # harmless on OpenAI-compatible wires). The newest turns win the character
  # budget — oldest are dropped first, so the array never explodes a prompt.
  module History
    module_function

    TURN_LIMIT  = 10
    CHAR_BUDGET = 24_000

    SKIP_KINDS = %w[thinking confirmation confirmation_follow_up theme_diff].freeze

    # @param before_turn [Turn, nil] when given, only turns strictly BEFORE it
    #   contribute — the orchestrator passes the live ai turn so the prompt
    #   arrives once (as the explicit final user message), not twice.
    # @return [Array<Hash>] [{role: "user"|"assistant", content: String}, …]
    def messages(conversation:, turn_limit: TURN_LIMIT, char_budget: CHAR_BUDGET, before_turn: nil)
      scope = conversation.turns.order(:position)
      scope = scope.where(position: ...before_turn.position) if before_turn
      turns = scope.last(turn_limit)

      per_turn = turns.map { |turn| turn_messages(turn) }
      budgeted = apply_budget(per_turn, char_budget)
      coalesce(budgeted.flatten)
    end

    # ── internals ──────────────────────────────────────────────────────────────

    def turn_messages(turn)
      turn.events.order(:position).filter_map do |event|
        next if SKIP_KINDS.include?(event.kind.to_s)

        case event.kind.to_s
        when "echo" then user_message(event)
        when "ai"   then ai_message(event)
        else             assistant_message(event)
        end
      end
    end

    def user_message(event)
      text = event.payload["text"].to_s.strip
      { role: "user", content: text } if text.present?
    end

    # An :ai event's payload carries typed blocks; text blocks speak verbatim,
    # structured blocks appear as bracketed markers so the model knows they were
    # shown without re-serializing chart data into the prompt.
    def ai_message(event)
      parts = Array(event.payload["blocks"]).map do |block|
        block = block.transform_keys(&:to_s) if block.respond_to?(:transform_keys)
        block["type"].to_s == "text" ? block["text"].to_s : "[#{block['type']}]"
      end
      content = parts.join("\n").strip
      { role: "assistant", content: content } if content.present?
    end

    def assistant_message(event)
      content = Pito::Mcp::EventText.call([ { kind: event.kind, payload: event.payload } ]).strip
      { role: "assistant", content: content } if content.present?
    end

    # Keep whole turns, newest first, until the character budget is spent —
    # a partial turn would strand a user line without its answer (or vice versa).
    def apply_budget(per_turn, char_budget)
      kept  = []
      spent = 0

      per_turn.reverse_each do |msgs|
        cost = msgs.sum { |m| m[:content].length }
        break if kept.any? && spent + cost > char_budget

        kept.unshift(msgs)
        spent += cost
      end

      kept
    end

    def coalesce(messages)
      messages.each_with_object([]) do |msg, acc|
        if acc.last && acc.last[:role] == msg[:role]
          acc.last[:content] = "#{acc.last[:content]}\n\n#{msg[:content]}"
        else
          acc << msg.dup
        end
      end
    end
  end
end
