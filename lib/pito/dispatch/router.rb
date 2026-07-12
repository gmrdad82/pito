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
    #      (Pito::Chat::Registry) now lives in config. A recognised chat tool with
    #      no chat dispatch (e.g. `find`) yields tool_not_implemented, exactly as
    #      the old Registry.lookup-nil path did.
    #   3. intercepts `--help` (tool man pages / the help easter egg) unchanged.
    #   4. binds kwargs: reply paths consume the ReplyBinding output that
    #      ToolDelegator threaded onto FollowUpContext#bound (previously
    #      advisory only, now consumed into the contract here); typed paths
    #      carry none.
    #   5. invokes the dispatch class through the uniform contract
    #      `call(kwargs:, context:) -> Pito::Chat::Result` and returns the Result
    #      to the caller UNCHANGED.
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
    class Router
      # @param input          [String]            the raw command / reconstructed reply text.
      # @param conversation   [Conversation]      the active conversation.
      # @param channel        [String, nil]       shift+tab channel scope.
      # @param period         [String, nil]       analytics window (e.g. "28d").
      # @param follow_up      [Pito::Chat::FollowUpContext, nil] present on `#<handle>` replies.
      # @param viewport_width [Integer, String, nil] scrollback width for list auto-fill.
      # @return [Pito::Chat::Result::Ok, Pito::Chat::Result::Error]
      def self.call(input:, conversation:, channel: nil, period: nil, follow_up: nil, viewport_width: nil)
        new(input:, conversation:, channel:, period:, follow_up:, viewport_width:).route
      end

      def initialize(input:, conversation:, channel: nil, period: nil, follow_up: nil, viewport_width: nil)
        @input          = input
        @conversation   = conversation
        @channel        = channel
        @period         = period
        @follow_up      = follow_up
        @viewport_width = viewport_width
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

        invoke(handler_class, message)
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
          viewport_width: @viewport_width
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
