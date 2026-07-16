# frozen_string_literal: true

module Pito
  module Dispatch
    # The agnostic Router — ONE config-driven execution path for chat tools and
    # for hashtag tool-replies ("no dispatchers with many if/else blocks";
    # routing IS a config lookup).
    #
    # Given an input string (a typed `<tool> <rest>` OR a reply's reconstructed
    # `<tool> <rest>` threaded with a Pito::Chat::FollowUpContext), it:
    #
    #   1. tokenizes + parses via Pito::Chat::Parser — this canonicalizes the tool
    #      (config/grammar aliases: `ls`→`list`, `analytics`→`analyze`) and decides
    #      new_turn vs unknown vs parse-error.
    #   2. resolves the tool's dispatch class from config/pito/tools.yml
    #      (`tools.<tool>.chat.dispatch`) — the map that used to live in Ruby
    #      (Pito::Chat::Registry) now lives in config. A recognised chat tool
    #      whose chat block declares no dispatch yields tool_not_implemented,
    #      exactly as the old Registry.lookup-nil path did (no shipped tool
    #      exhibits that shape today — the gate is defensive; see
    #      spec/dispatch/router_spec.rb's stubbed-config pin).
    #   3. intercepts `--help` (tool man pages / the help easter egg) unchanged.
    #   4. binds kwargs: reply paths consume the ReplyBinding output that
    #      ToolDelegator threaded onto FollowUpContext#bound (previously
    #      advisory only, now consumed into the contract here); typed paths
    #      carry none.
    #   5. invokes the dispatch class through the uniform contract
    #      `call(kwargs:, context:) -> Pito::Chat::Result` and returns the Result
    #      to the caller UNCHANGED — with one exception, the soft-fail fallback:
    #
    # ── NL soft-fail fallback (3.0.1 P7) ──
    #
    # A handler that recognised its verb but couldn't act on a FREE-TEXT-looking
    # body ("show me my tekken vids") returns Result::Error with
    # `nl_fallback: true` instead of a crisp local error. #route_verb intercepts
    # that marker and re-invokes Pito::Chat::Handlers::Unknown with the ORIGINAL
    # raw utterance, so the full NL gate (router score → mapper → auto-run /
    # did-you-mean / huh) runs exactly as if the verb had never been captured.
    # Loop guard: a dispatch that IS already an NL retry (`nl_retry: true` — a
    # mapped command re-entering from Unknown#run_now or
    # Pito::Confirmation::Executor#confirm_nl_run) never re-enters the gate;
    # the marker returns to that caller, which degrades it (run_now → the
    # did-you-mean copy; confirm → the marker's own crisp error text).
    #
    # Surface availability: the CHAT surface is gated here — a tool reaches the
    # dispatch step only when the parser recognised it as a chat tool AND config
    # declares a chat dispatch class. The REPLY surface's per-target availability
    # (the Matrix `invalid_action` gate) stays in Pito::FollowUp::ToolDelegator,
    # which runs before this Router and is preserved exactly.
    #
    # Adding a tool needs ZERO edits here: declare the tool + `chat.dispatch:`
    # in config and ship a handler class that answers the uniform contract
    # (every Pito::Chat::Handler does, via its base `self.call`).
    #
    # ── `nl_eligible` vs `nl_retry` (3.0.1 reconciliation fix) ──
    #
    # Both gate the SAME soft-fail marker but answer different questions.
    # `nl_retry` is the LOOP GUARD: true only when this dispatch is ITSELF an
    # NL-mapped/confirmed re-entry (Unknown#run_now, Executor#confirm_nl_run) —
    # it tells the ROUTER "if the handler soft-fails, hand the marker back to
    # ME rather than re-entering the gate". `nl_eligible` (default true) tells
    # the HANDLER (via Context) whether its body is even CANDIDATE free text in
    # the first place — several Pito::FollowUp::Handlers::* (GameSimilar,
    # ChannelGames, GameChannels, GameLinkedVideos, GameImported) dispatch a
    # RECONSTRUCTED `show <noun> <ref>` command with NO FollowUpContext (so
    # Show's title-resolution ladder still runs, exactly as free chat would),
    # but that reconstructed ref was never actually typed by the owner — a
    # title-ladder miss there must stay the crisp not-found (consume: false),
    # never leak into the NL gate as if it were a garbled sentence. Those
    # callers pass `nl_eligible: false`; Show/List read it as `nl_eligible?`
    # and skip marker emission entirely, so the Router-level soft-fail branch
    # below never even sees a marker to intercept.
    class Router
      # @param input          [String]            the raw command / reconstructed reply text.
      # @param conversation   [Conversation]      the active conversation.
      # @param channel        [String, nil]       shift+tab channel scope.
      # @param period         [String, nil]       analytics window (e.g. "28d").
      # @param follow_up      [Pito::Chat::FollowUpContext, nil] present on `#<handle>` replies.
      # @param viewport_width [Integer, String, nil] scrollback width for list auto-fill.
      # @param nl_retry       [Boolean] true when this dispatch executes an NL-mapped
      #                       command (Unknown#run_now / Executor#confirm_nl_run) —
      #                       the loop guard: a soft-fail marker is returned to the
      #                       caller instead of re-entering the NL gate.
      # @param nl_eligible    [Boolean] false when the input, though shaped like a typed
      #                       command, is a RECONSTRUCTED follow-up dispatch rather than
      #                       owner-typed free text — see the class header. Threaded to
      #                       handlers via Context#nl_eligible; never re-read by the
      #                       Router itself.
      # @return [Pito::Chat::Result::Ok, Pito::Chat::Result::Error]
      def self.call(input:, conversation:, channel: nil, period: nil, follow_up: nil, viewport_width: nil, nl_retry: false, nl_eligible: true)
        new(input:, conversation:, channel:, period:, follow_up:, viewport_width:, nl_retry:, nl_eligible:).route
      end

      def initialize(input:, conversation:, channel: nil, period: nil, follow_up: nil, viewport_width: nil, nl_retry: false, nl_eligible: true)
        @input          = input
        @conversation   = conversation
        @channel        = channel
        @period         = period
        @follow_up      = follow_up
        @viewport_width = viewport_width
        @nl_retry       = nl_retry
        @nl_eligible    = nl_eligible
      end

      def route
        message = parse
        return message if message.is_a?(Pito::Chat::Result::Error)

        case message.kind
        when :new_turn then route_verb(message)
        when :unknown  then invoke(Pito::Chat::Handlers::Unknown, message)
        end
      end

      private

      def parse
        tokens = Pito::Lex::KeywordSanitizer.call(Pito::Lex::Lexer.call(@input))
        Pito::Chat::Parser.call(tokens, raw: @input, conversation: @conversation)
      rescue Pito::Chat::Parser::NotAChatMessage
        Pito::Chat::Result::Error.new(
          message_key: "pito.chat.errors.misrouted_slash",
          message_args: { raw: @input }
        )
      end

      def route_verb(message)
        handler_class = dispatch_class_for(message.tool)

        if handler_class.nil?
          return Pito::Chat::Result::Error.new(
            message_key: "pito.chat.errors.tool_not_implemented",
            message_args: { tool: message.tool }
          )
        end

        help = help_page(message)
        return help if help

        result = invoke(handler_class, message)
        return result unless soft_fail?(result)
        # Loop guard: an NL-mapped command that itself soft-fails returns its
        # marker to the mapped-command caller (Unknown#run_now degrades it to
        # the did-you-mean copy; confirm_nl_run renders its crisp error text) —
        # the gate never recurses.
        return result if @nl_retry

        # Soft-fail fallback (see the class header): re-run the ORIGINAL raw
        # utterance through the full NL gate as if the verb had never been
        # captured. Unknown reads message.raw — the untouched input.
        invoke(Pito::Chat::Handlers::Unknown, message)
      end

      # The "verb recognized, body not actionable" soft-fail marker (see
      # Pito::Chat::Result::Error#nl_fallback).
      def soft_fail?(result)
        result.is_a?(Pito::Chat::Result::Error) && result.nl_fallback
      end

      # Resolves `tools.<tool>.chat.dispatch` from config to a handler Class, or
      # nil when the tool is unknown to config or declares no chat dispatch. The
      # nil case mirrors the old Pito::Chat::Registry.lookup miss → the caller
      # returns tool_not_implemented.
      def dispatch_class_for(tool)
        class_string =
          begin
            Pito::Dispatch::Config.tool(tool).dig(:chat, :dispatch)
          rescue KeyError
            nil
          end
        return nil if class_string.nil?

        "Pito::#{class_string}".constantize
      end

      # `--help` / `-h` interception, byte-for-byte from the retired
      # Pito::Chat::Dispatcher: `help --help` is the easter-egg nonsense page;
      # `<tool> [noun] --help` renders the tool man page. Returns a Result::Ok, or
      # nil to fall through to normal dispatch (CommandHelp gave no page).
      def help_page(message)
        return nil unless message.raw.match?(/(?:\A|\s)--help(?:\s|\z)/)

        if message.tool == :help
          body    = Pito::Slash::HelpBuilder.nonsense_body
          payload = { "html" => true, "body" => body }
          return Pito::Chat::Result::Ok.new(events: [ { kind: :system, payload: } ])
        end

        noun    = extract_noun(message)
        payload = Pito::MessageBuilder::CommandHelp.call(message.tool, noun:)
        # A token that isn't a real noun page (`link #3 to game #5 --help` extracts
        # :to) must not send a --help message into handler execution — fall back to
        # the tool-level page rather than dispatching.
        payload ||= Pito::MessageBuilder::CommandHelp.call(message.tool, noun: nil) if noun
        payload ? Pito::Chat::Result::Ok.new(events: [ { kind: :system, payload: } ]) : nil
      end

      # The single uniform invocation: bind kwargs + context, hand off to the
      # dispatch class's `call(kwargs:, context:)`, return the Result unchanged.
      def invoke(handler_class, message)
        handler_class.call(kwargs: bound_kwargs, context: context_for(message))
      end

      # Reply paths consume FollowUpContext#bound — the ReplyBinding output
      # ToolDelegator resolved from the tool's `reply.targets.<target>.ref/args`
      # config. Typed free-chat paths carry no pre-bound kwargs.
      def bound_kwargs
        @follow_up ? @follow_up.bound : {}
      end

      def context_for(message)
        Pito::Dispatch::Context.new(
          message:        message,
          conversation:   @conversation,
          channel:        @channel,
          period:         @period,
          follow_up:      @follow_up,
          viewport_width: @viewport_width,
          nl_eligible:    @nl_eligible
        )
      end

      # Extract the noun token (first plain word after the tool) from the raw
      # input, skipping `--help` / `-h` flags. Returns a Symbol or nil.
      #
      # The lexer splits "--help" into :unknown(-) :unknown(-) :word("help"), so
      # body_tokens alone can't be trusted; instead scan the raw string for the
      # first word not preceded by a dash.
      #
      #   "delete game --help"   → :game
      #   "delete --help"        → nil
      #   "import videos --help" → :videos
      #   "show #3 --help"       → nil (an id ref is not a noun → tool-level page)
      #   "show @handle --help"  → nil (a handle ref is not a noun)
      def extract_noun(message)
        raw_after_verb = message.raw.to_s.sub(/\A\s*\S+\s*/, "")

        raw_after_verb.split.each do |token|
          next if token.start_with?("-")
          next if token.match?(/\A\d+\z/)
          next if token.start_with?('"')
          # Entity references (numeric `#id` / `@handle`) are targets, not nouns:
          # skip them so `show #3 --help` / `show @foo --help` render the tool page
          # instead of mis-parsing the ref as an unknown noun and falling through.
          next if token.start_with?("#", "@")

          return token.downcase.to_sym
        end

        nil
      end
    end
  end
end
