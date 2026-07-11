# frozen_string_literal: true

module Pito
  module Mcp
    # The two READER tools (verbs.yml `mcp_readers:`) — pito_conversations and
    # pito_messages. Unlike verb-backed tools they dispatch NOTHING through the
    # Router: they SELECT persisted rows and project them through EventText.
    #
    # Scope: `source: "app"` ONLY — the owner's real scrollback. The MCP anchor
    # (source: "mcp") never appears, in either direction. Read-only: plain
    # SELECTs, no writes.
    #
    # pito is PULL-ONLY — there is no push to the chat client. Because every
    # "delayed" result (an analytics fill, a sync summary) is a persisted payload
    # REPLACE, pito_messages reading the CURRENT rows always reflects whatever has
    # already landed; the model calls again for fresher state.
    module Readers
      module_function

      DEFAULT_LIMIT = 30
      MAX_LIMIT     = 200

      # Scrollback events an MCP client can read — exclude the spinner + theme
      # diffs (UI-only chrome). Echo (the owner's own input) is kept so the
      # transcript shows both sides.
      READABLE_KINDS = (::Event::KINDS - %w[thinking theme_diff]).freeze

      def call(tool, args = {})
        case tool.to_s
        when "pito_conversations" then conversations
        when "pito_messages"      then messages(args || {})
        else raise Executor::UnknownTool, tool.to_s
        end
      end

      # ── pito_conversations ─────────────────────────────────────────────────────

      def conversations
        Executor::Result.new(text: conversations_text(::Conversation.recency_groups), is_error: false)
      end

      def conversations_text(groups)
        sections = [ section("Recent", groups[:recent]), section("Older", groups[:older]) ].compact
        sections.empty? ? "No conversations yet." : sections.join("\n\n")
      end

      def section(label, convs)
        return nil if convs.blank?

        lines = convs.map { |c| "- #{c.uuid} — #{c.display_name} (#{ago(c.last_activity_at)})" }
        "#{label}:\n#{lines.join("\n")}"
      end

      # ── pito_messages ──────────────────────────────────────────────────────────

      def messages(args)
        uuid         = args["conversation_uuid"]
        conversation = resolve_conversation(uuid)
        return missing_conversation(uuid) if conversation.nil?

        events = conversation.events.where(kind: READABLE_KINDS).order(:position).last(clamp_limit(args["limit"]))
        header = %(Messages in "#{conversation.display_name}" (newest last):)
        lines  = events.filter_map { |event| project_message(event) }
        body   = lines.empty? ? "(no messages yet)" : lines.join("\n\n")
        Executor::Result.new(text: "#{header}\n\n#{body}", is_error: false)
      end

      def project_message(event)
        text = EventText.call([ event ])
        return nil if text.blank?

        "#{role(event.kind)}: #{text}"
      end

      def role(kind)
        kind.to_s == "echo" ? "you" : "pito"
      end

      def resolve_conversation(uuid)
        if uuid.present?
          ::Conversation.where(source: "app").find_by(uuid: uuid.to_s.downcase)
        else
          ::Conversation.by_recent_activity.first
        end
      end

      def missing_conversation(uuid)
        text = uuid.present? ? "No conversation found for uuid #{uuid}." : "No conversations yet."
        Executor::Result.new(text: text, is_error: uuid.present?)
      end

      # ── helpers ────────────────────────────────────────────────────────────────

      def clamp_limit(value)
        (value.presence || DEFAULT_LIMIT).to_i.clamp(1, MAX_LIMIT)
      end

      def ago(time)
        return "unknown" if time.blank?

        "#{ActionController::Base.helpers.time_ago_in_words(time)} ago"
      rescue StandardError
        time.to_s
      end
    end
  end
end
