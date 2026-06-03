# frozen_string_literal: true

module Pito
  module Slash
    module Handlers
      # /config <provider> [key=value ...]
      #
      # Getter (no kwargs):
      #   /config google  →  shows credential status (present/missing)
      #
      # Setter (one or more kwargs):
      #   /config google client_id=xxx client_secret=xxx redirect_uri=xxx
      #
      # Any subset of kwargs is accepted for the setter (min 1).
      # Sensitive values (client_id, client_secret) are masked to *** in
      # the echo by ChatController before this handler runs.
      class Config < Pito::Slash::Handler
        self.verb = :config
        self.description_key = "pito.slash.config.descriptions.config"

        grammar do
          literal :provider, source: :config_providers
          kv :settings, source: :config_keys, repeatable: true, optional: true
          auth :authenticated_only
          description_key "pito.grammar.slash.config"
        end

        KNOWN_PROVIDERS = %w[google voyage igdb webhook].freeze

        # Maps each provider's supported kwargs to their AppSetting writers.
        PROVIDER_SETTERS = {
          "google" => {
            client_id:     ->(v) { AppSetting.singleton_row.update!(google_oauth_client_id: v) },
            client_secret: ->(v) { AppSetting.singleton_row.update!(google_oauth_client_secret: v) },
            redirect_uri:  ->(v) { AppSetting.google_oauth_redirect_uri = v },
            api_key:       ->(v) { AppSetting.google_api_key = v }
          },
          "voyage" => {
            api_key: ->(v) { AppSetting.singleton_row.update!(voyage_api_key: v) }
          },
          "igdb" => {
            client_id:     ->(v) { AppSetting.igdb_client_id = v },
            client_secret: ->(v) { AppSetting.igdb_client_secret = v }
          },
          "webhook" => {
            slack:   ->(v) { AppSetting.slack_webhook_url = v },
            discord: ->(v) { AppSetting.discord_webhook_url = v }
          }
        }.freeze

        # Status readers for the getter display (returns a Hash of label → value/status).
        PROVIDER_STATUS = {
          "google" => -> {
            {
              "Client ID"     => status_flag(Pito::Credentials.google_oauth_client_id),
              "Client Secret" => status_flag(Pito::Credentials.google_oauth_client_secret),
              "Redirect URI"  => Pito::Credentials.google_oauth_redirect_uri.presence || ok_missing(:missing),
              "API Key"       => status_flag(Pito::Credentials.google_api_key)
            }
          },
          "voyage" => -> {
            { "API Key" => status_flag(Pito::Credentials.voyage_api_key) }
          },
          "igdb" => -> {
            {
              "Client ID"     => status_flag(Pito::Credentials.igdb_client_id),
              "Client Secret" => status_flag(Pito::Credentials.igdb_client_secret)
            }
          },
          "webhook" => -> {
            {
              "Slack"   => Pito::Credentials.slack_webhook_url.presence || ok_missing(:missing),
              "Discord" => Pito::Credentials.discord_webhook_url.presence || ok_missing(:missing)
            }
          }
        }.freeze

        # Sensitive keys whose values are masked (***) in the echo.
        MASKED_KEYS = %w[client_id client_secret api_key].freeze

        def call
          return show_help if help?

          provider = invocation.args.first.to_s.downcase

          unless KNOWN_PROVIDERS.include?(provider)
            return Pito::Slash::Result::Error.new(
              message_key:  "pito.slash.config.errors.unknown_provider",
              message_args: { provider: provider.presence || "(none)" }
            )
          end

          kwargs = invocation.kwargs
          kwargs.empty? ? show_status(provider) : set_values(provider, kwargs)
        end

        def show_help
          provider = invocation.args.find { |a| KNOWN_PROVIDERS.include?(a.to_s.downcase) }

          return google_help_events if provider.to_s == "google"

          return general_help_events if provider.blank?

          key = "pito.slash.config.help.providers.#{provider}"
          Pito::Slash::Result::Ok.new(events: [
            { kind: "system", payload: { text: I18n.t(key) } }
          ])
        end

        def general_help_events
          Pito::Slash::Result::Ok.new(events: [
            {
              kind:    "system",
              payload: {
                body:       I18n.t("pito.slash.config.help.general.body"),
                table_rows: KNOWN_PROVIDERS.map do |p|
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

        def google_help_events
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

        private

        def show_status(provider)
          pairs = PROVIDER_STATUS[provider].call
          missing_text = I18n.t("pito.slash.config.status.missing")

          table_rows = pairs.map do |label, val|
            {
              key:         "#{label}:",
              value:       val,
              key_class:   "text-fg-dim",
              value_class: val == missing_text ? "text-red" : "text-green"
            }
          end

          Pito::Slash::Result::Ok.new(events: [
            {
              kind:    :system,
              payload: {
                body:       I18n.t("pito.slash.config.status.section.#{provider}",
                                   default: "#{provider.capitalize} credentials"),
                table_rows:
              }
            }
          ])
        end

        def set_values(provider, kwargs)
          setters = PROVIDER_SETTERS[provider]
          unknown = kwargs.keys.map(&:to_sym) - setters.keys

          if unknown.any?
            return Pito::Slash::Result::Error.new(
              message_key:  "pito.slash.config.errors.unknown_keys",
              message_args: { keys: unknown.map(&:to_s).join(", "), provider: provider }
            )
          end

          kwargs.each { |key, value| setters[key.to_sym]&.call(value.to_s) }
          Pito::Credentials.invalidate!

          Pito::Slash::Result::Ok.new(events: [
            {
              kind:    "system",
              payload: {
                message_key:  "pito.slash.config.updated",
                message_args: { provider: provider, keys: kwargs.keys.map(&:to_s).join(", ") }
              }
            }
          ])
        end

        def self.status_flag(value)
          ok_missing(value.present? ? :ok : :missing)
        end

        def self.ok_missing(key)
          I18n.t("pito.slash.config.status.#{key}")
        end
      end
    end
  end
end
