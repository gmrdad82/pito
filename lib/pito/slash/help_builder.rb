# frozen_string_literal: true

module Pito
  module Slash
    # Universal man-page-style --help renderer for slash commands.
    #
    # Every /<tool> --help now produces a
    # `.pito-help-block` HTML payload via Pito::MessageBuilder::ManPage instead
    # of the old body:/table_rows:/info_lines: hash format.
    #
    # Called by the Dispatcher when the raw input contains --help or -h,
    # BEFORE the normal handler executes, so no command can produce side
    # effects while the user is just asking for help.
    #
    # Rendering rules (checked in order):
    #   1. /help --help / /themes --help  → man-page nonsense easter egg
    #   2. /config … --help               → delegated to Config#show_help (the
    #      canonical per-provider renderer: key tables, google /connect hint,
    #      fx live-showcase rows, motion on/off, timezone, general overview)
    #   3. Any other command              → generic usage + description (man style)
    module HelpBuilder
      # Presentational grouping for the /config --help overview (T10.57).
      # Group keys map to i18n titles under pito.slash.config.help.general.groups;
      # commands are untouched — every entry is still `/config <provider>`.
      # AI config has exactly ONE entry here (owner: no per-provider spillage).
      CONFIG_PROVIDER_GROUPS = {
        "ai"      => %w[ai tavily],
        "sources" => %w[google igdb],
        "profile" => %w[webhook sound timezone]
      }.freeze

      # Ordered provider list for /config --help; derived from the groups so the
      # overview and provider extraction can never drift apart. Mirrors the i18n
      # copy order.
      ALL_CONFIG_PROVIDERS = CONFIG_PROVIDER_GROUPS.values.flatten.freeze

      class << self
        def call(invocation:)
          tool     = invocation.tool.to_s
          provider = extract_provider(invocation.raw, tool)

          return nonsense_help if %w[help themes].include?(tool)

          # /config <provider> --help and /config --help both delegate to the
          # Config handler's #show_help — the single source of truth for every
          # provider man page (google's /connect hint, the fx live showcase rows,
          # the motion on/off page, the timezone page, and the generic key tables).
          # The interceptor fires BEFORE the handler runs, so without this
          # delegation the rich provider pages (fx/motion especially) were never
          # reached and every toggle/enum provider fell back to generic help.
          return config_help(invocation, provider) if tool == "config"

          # Any handler that overrides #show_help renders its OWN rich man page —
          # the same delegation /config uses, generalised (checked dynamically, no
          # hardcoded list) so no authored slash `--help` page is dead. This is how
          # /jobs (subcommands), /games (import), and /rename (arguments) get their
          # full pages instead of the bare generic usage+description.
          handler_class = Pito::Slash::Registry.lookup(invocation.tool)
          return handler_help(invocation, handler_class) if overrides_show_help?(handler_class)

          generic_command_help(tool)
        end

        # Returns the raw HTML for the nonsense "manual's manual" man page.
        # Exposed publicly so the chat dispatcher can embed it without duplicating
        # the copy logic.
        def nonsense_body
          title = I18n.t("pito.slash.help.nonsense_title")
          rows  = I18n.t("pito.slash.help.nonsense").map { |k, v| [ k.to_s, v ] }
          Pito::MessageBuilder::ManPage.render(
            usage:  title,
            groups: [ [ "Commands:", rows ] ]
          )
        end

        private

        def nonsense_help
          ok(nonsense_body)
        end

        # ── /config <provider> --help and /config --help ───────────────────────

        # Delegate to the Config handler's #show_help, the canonical renderer for
        # every provider man page. We build a synthetic invocation whose first
        # positional arg is the cleaned provider (or none, for general help), so
        # show_help's `case provider` lands on the right page regardless of how
        # --help/-h tokenised into the raw input. No conversation is needed — the
        # man-page renderers read only i18n copy and AppSetting constants.
        def config_help(invocation, provider)
          synthetic = Pito::Slash::Invocation.new(
            tool:   :config,
            args:   provider ? [ provider ] : [],
            kwargs: {},
            raw:    invocation.raw
          )

          Pito::Slash::Handlers::Config.new(
            invocation:    synthetic,
            conversation:  nil,
            authenticated: true
          ).show_help
        end

        # ── Handler-delegated help (handlers overriding #show_help) ─────────────

        # True when the handler class defines its own #show_help (not the inherited
        # base default) — i.e. it authored a real man page worth rendering.
        def overrides_show_help?(handler_class)
          return false if handler_class.nil?

          handler_class.instance_method(:show_help).owner != Pito::Slash::Handler
        end

        # Render a handler's own #show_help man page. No conversation is needed —
        # these renderers read only i18n copy (mirrors the /config delegation).
        # `#show_help` is public on some handlers and private on others, so call it
        # via send (the override check already proved it is defined).
        def handler_help(invocation, handler_class)
          handler_class.new(
            invocation:    invocation,
            conversation:  nil,
            authenticated: true
          ).send(:show_help)
        end

        # ── Generic per-command help ───────────────────────────────────────────

        def generic_command_help(tool)
          usage = I18n.t("pito.slash.#{tool}.help.usage",       default: "/#{tool}")
          desc  = I18n.t("pito.slash.#{tool}.help.description", default: I18n.t("pito.grammar.slash.#{tool}", default: ""))

          groups = []
          groups << [ "Description:", [ [ "/#{tool}", desc ] ] ] if desc.present?
          groups << [ "Options:",     [ [ "--help", "Print this help message" ] ] ]

          body = Pito::MessageBuilder::ManPage.render(usage:, groups:)
          ok(body)
        end

        # ── Provider extraction ────────────────────────────────────────────────

        # Parses the provider from the raw slash input, ignoring --help/-h tokens.
        # Returns nil when the tool is not "config" or no known provider is present.
        def extract_provider(raw, tool)
          return nil unless tool == "config"

          tokens = raw.to_s.split
          tokens.find do |t|
            clean = t.gsub(/--help|-h\b/, "").strip.downcase
            ALL_CONFIG_PROVIDERS.include?(clean) && clean.present?
          end&.gsub(/--help|-h\b/, "")&.strip&.downcase
        end

        # ── Result builder ─────────────────────────────────────────────────────

        def ok(body)
          Pito::Slash::Result::Ok.new(events: [ {
            kind:    :system,
            payload: { "html" => true, "body" => body }
          } ])
        end
      end
    end
  end
end
