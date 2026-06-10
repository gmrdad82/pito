# frozen_string_literal: true

module Pito
  module Slash
    # P56 — Universal --help renderer.
    #
    # Called by the Dispatcher when the raw input contains --help or -h,
    # BEFORE the normal handler executes, so no command can produce side
    # effects while the user is just asking for help.
    #
    # Rendering rules (checked in order):
    #   1. /help --help          → witty nonsense kv-table
    #   2. /config <provider> --help → provider-specific key kv-table
    #   3. /config --help        → general config overview (body + provider table)
    #   4. Any other command     → per-command usage line + description as kv-table
    module HelpRenderer
      KNOWN_CONFIG_PROVIDERS = %w[google voyage igdb webhook sound fx].freeze

      class << self
        # Returns the raw payload hash for the /help --help nonsense page.
        # Shared by the slash dispatcher (via #call) and the chat dispatcher
        # so both render from the same i18n copy without duplication.
        def nonsense_payload
          rows = I18n.t("pito.slash.help.nonsense").map do |key, value|
            { key: key.to_s, value: value }
          end
          {
            body:       I18n.t("pito.slash.help.nonsense_title"),
            table_rows: rows
          }
        end

        def call(invocation:, authenticated:)
          verb = invocation.verb.to_s

          # Extract the provider from the raw input — we cannot rely on
          # invocation.args because the parser slurps "--help"/"-h" tokens into
          # the last positional arg (e.g. "igdb--help" instead of "igdb").
          provider = extract_provider(invocation.raw)

          if verb == "help"
            return nonsense_help
          end

          if verb == "config"
            return provider_help(provider) if provider
            return general_config_help
          end

          command_help(verb)
        end

        private

        # ── /help --help ───────────────────────────────────────────────────────

        def nonsense_help
          Pito::Slash::Result::Ok.new(events: [
            {
              kind:    "system",
              payload: nonsense_payload
            }
          ])
        end

        # ── /config <provider> --help ──────────────────────────────────────────

        def provider_help(provider)
          if provider == "google"
            return google_provider_help
          end

          key_rows = provider_key_rows(provider)

          Pito::Slash::Result::Ok.new(events: [
            {
              kind:    "system",
              payload: {
                body:       "/config #{provider} [key=value …]",
                table_rows: key_rows,
                info_lines: [ I18n.t("pito.slash.config.help.general.info_lines").first ]
              }
            }
          ])
        end

        def provider_key_rows(provider)
          keys = Pito::Grammar::Vocabularies.provider_keys(provider)
          keys.map do |key|
            i18n_key = "pito.slash.config.help.providers.#{provider}.keys.#{key}"
            description = I18n.t(i18n_key, default: "")
            { key: "#{key}=", value: description }
          end
        end

        def google_provider_help
          Pito::Slash::Result::Ok.new(events: [
            {
              kind:    "system",
              payload: {
                body:       "/config google [key=value …]",
                table_rows: [
                  { key: "client_id=",     value: I18n.t("pito.slash.config.help.providers.google.keys.client_id") },
                  { key: "client_secret=", value: I18n.t("pito.slash.config.help.providers.google.keys.client_secret") },
                  { key: "redirect_uri=",  value: I18n.t("pito.slash.config.help.providers.google.keys.redirect_uri") },
                  { key: "api_key=",       value: I18n.t("pito.slash.config.help.providers.google.keys.api_key") }
                ],
                info_lines: [
                  I18n.t("pito.slash.config.help.providers.google.omit_hint")
                ],
                suggestion: {
                  pre:       I18n.t("pito.slash.config.help.providers.google.suggestion.pre"),
                  code:      "/connect",
                  post:      I18n.t("pito.slash.config.help.providers.google.suggestion.post"),
                  shortcut:  "ctrl+/",
                  run_label: I18n.t("pito.event.suggestion.run_label"),
                  run_cmd:   "/connect"
                }
              }
            }
          ])
        end

        # ── /config --help (general) ───────────────────────────────────────────

        def general_config_help
          all_providers = KNOWN_CONFIG_PROVIDERS
          Pito::Slash::Result::Ok.new(events: [
            {
              kind:    "system",
              payload: {
                body:       I18n.t("pito.slash.config.help.general.body"),
                table_rows: all_providers.map do |p|
                  {
                    key:   p,
                    value: I18n.t("pito.slash.config.help.general.providers.#{p}")
                  }
                end,
                info_lines: I18n.t("pito.slash.config.help.general.info_lines")
              }
            }
          ])
        end

        # ── Provider extraction ────────────────────────────────────────────────

        # Parse the provider from the raw slash input, ignoring --help/-h tokens.
        # Returns nil when no known provider is present.
        def extract_provider(raw)
          # Strip the verb and --help/-h tokens, then look for a known provider.
          tokens = raw.to_s.split
          tokens.find do |t|
            clean = t.gsub(/--help|-h\b/, "").strip.downcase
            KNOWN_CONFIG_PROVIDERS.include?(clean) && clean.present?
          end&.gsub(/--help|-h\b/, "")&.strip&.downcase
        end

        # ── Generic per-command help ───────────────────────────────────────────

        def command_help(verb)
          usage_key = "pito.slash.#{verb}.help.usage"
          desc_key  = "pito.slash.#{verb}.help.description"

          usage = I18n.t(usage_key, default: "/#{verb}")
          desc  = I18n.t(desc_key,  default: I18n.t("pito.grammar.slash.#{verb}", default: ""))

          Pito::Slash::Result::Ok.new(events: [
            {
              kind:    "system",
              payload: {
                body:       usage,
                table_rows: desc.present? ? [ { key: "/#{verb}", value: desc } ] : []
              }
            }
          ])
        end
      end
    end
  end
end
