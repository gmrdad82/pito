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
    # @param must_include_turn [Turn, nil] a turn GUARANTEED into the result —
    #   the `#a7 @ai …` reply anchor: prepended when it has scrolled out of the
    #   window, and immune to the budget's oldest-first drop.
    # @return [Array<Hash>] [{role: "user"|"assistant", content: String}, …]
    def messages(conversation:, turn_limit: TURN_LIMIT, char_budget: CHAR_BUDGET, before_turn: nil, must_include_turn: nil)
      scope = conversation.turns.order(:position)
      scope = scope.where(position: ...before_turn.position) if before_turn
      turns = scope.last(turn_limit)

      pinned = must_include_turn if must_include_turn && turns.none? { |t| t.id == must_include_turn.id }
      pinned_index = pinned ? 0 : turns.index { |t| must_include_turn && t.id == must_include_turn.id }

      per_turn = turns.map { |turn| turn_messages(turn) }
      per_turn.unshift(turn_messages(pinned)) if pinned
      budgeted = apply_budget(per_turn, char_budget, pinned_index:)
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
        case block["type"].to_s
        when "text" then block["text"].to_s
        # Carry the command so the model never imitates a bare "[suggestion]"
        # marker as if it were prose (owner saw exactly that).
        when "suggestion" then "[suggested command: #{block['command']}]"
        else "[#{block['type']} block shown]"
        end
      end
      content = parts.join("\n").strip
      { role: "assistant", content: content } if content.present?
    end

    def assistant_message(event)
      content = Pito::Mcp::EventText.call([ { kind: event.kind, payload: event.payload } ]).strip
      { role: "assistant", content: content } if content.present?
    end

    # Keep whole turns, newest first, until the character budget is spent —
    # a partial turn would strand a user line without its answer (or vice
    # versa). The pinned anchor turn (pinned_index) survives regardless — it is
    # charged up front and kept at its chronological position.
    def apply_budget(per_turn, char_budget, pinned_index: nil)
      kept    = []
      spent   = pinned_index ? per_turn[pinned_index].sum { |m| m[:content].length } : 0
      stopped = false

      per_turn.each_with_index.reverse_each do |msgs, idx|
        if idx == pinned_index
          kept.unshift(msgs) # already charged; immune to the drop
          next
        end
        next if stopped

        cost = msgs.sum { |m| m[:content].length }
        if kept.any? && spent + cost > char_budget
          stopped = true
          next
        end

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
