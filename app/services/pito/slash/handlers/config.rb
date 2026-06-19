# frozen_string_literal: true

module Pito
  module Slash
    module Handlers
      # Handler for `/config <provider> [key=value …]`.
      #
      # Providers fall into two categories:
      #
      # **Credential providers** (`google`, `voyage`, `igdb`, `webhook`):
      # - **Getter** (no kwargs): `/config google` → status table (OK/MISSING per key).
      # - **Setter** (≥1 kwarg): `/config google client_id=x` → writes via `AppSetting` writers
      #   and invalidates the `Pito::Credentials` cache.
      # - Unknown kwargs return `Result::Error` with key `pito.slash.config.errors.unknown_keys`.
      #
      # **Toggle providers** (`sound`, `fx`):
      # - **Getter** (no arg): `/config sound` → current on/off state.
      # - **Setter**: `/config sound on|off` (synonyms: true/false/enable/disable/enabled/disabled)
      #   → writes via `AppSetting` and broadcasts a settings-update cable event.
      # - Invalid toggle value → `Result::Error` with key `pito.slash.config.errors.invalid_toggle_value`.
      #
      # Bare `/config` (no provider) → general overview table of all providers.
      # Unknown provider → `Result::Error` with key `pito.slash.config.errors.unknown_provider`.
      #
      # Sensitive keys (`client_id`, `client_secret`, `api_key`) are masked to `***`
      # in the echo by `ChatController#mask_config_credentials` *before* this handler runs.
      #
      # `show_help` is overridden: `/config --help` renders the general provider table;
      # `/config google --help` renders Google-specific key table with `/connect` suggestion.
      class Config < Pito::Slash::Handler
        self.verb = :config
        self.description_key = "pito.slash.config.descriptions.config"

        grammar do
          literal :provider, source: :config_providers
          enum    :state,    source: :on_off,      optional: true,              when: { provider: %w[sound fx] }
          kv      :settings, source: :config_keys, repeatable: true, optional: true, when: { provider: %w[google voyage igdb webhook] }
          auth :authenticated_only
          description_key "pito.grammar.slash.config"
        end

        KNOWN_PROVIDERS   = %w[google voyage igdb webhook].freeze
        TOGGLE_PROVIDERS  = %w[sound fx].freeze

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

        # The timezone provider stores a single value (an IANA zone) rather than
        # key/value credentials, so it has its own getter/setter path.
        TIMEZONE_PROVIDER = "timezone"

        def call
          return show_help if help?

          # Time zone takes a major-city name (resolved to an IANA zone). Forms:
          #   /config timezone=Madrid   (kv) — single-word cities
          #   /config timezone Madrid   (bare)
          #   /config timezone          (getter — shows the current zone)
          return handle_timezone if timezone_command?

          provider = invocation.args.first.to_s.downcase

          # Bare /config with no provider shows the general overview.
          return general_help_events if provider.blank?

          unless known_providers.include?(provider)
            return Pito::Slash::Result::Error.new(
              message_key:  "pito.slash.config.errors.unknown_provider",
              message_args: { provider: provider }
            )
          end

          return handle_toggle(provider) if TOGGLE_PROVIDERS.include?(provider)

          kwargs = invocation.kwargs
          kwargs.empty? ? show_status(provider) : set_values(provider, kwargs)
        end

        def show_help
          provider = invocation.args.find { |a| known_providers.include?(a.to_s.downcase) }

          return google_help_events if provider.to_s == "google"

          return general_help_events if provider.blank?

          key = "pito.slash.config.help.providers.#{provider}"
          Pito::Slash::Result::Ok.new(events: [
            { kind: "system", payload: { text: I18n.t(key) } }
          ])
        end

        def general_help_events
          all_providers = known_providers
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

        # Handle /config sound [on|off] and /config fx [on|off].
        def handle_toggle(provider)
          raw_state = invocation.args[1].to_s.strip.downcase

          # Getter — no argument supplied.
          if raw_state.empty?
            return show_toggle_status(provider)
          end

          bool = parse_on_off(raw_state)
          if bool.nil?
            return Pito::Slash::Result::Error.new(
              message_key:  "pito.slash.config.errors.invalid_toggle_value",
              message_args: { value: raw_state }
            )
          end

          if provider == "sound"
            AppSetting.sound_enabled = bool
          else
            AppSetting.fx_enabled = bool
          end

          broadcaster = Pito::Stream::Broadcaster.new(conversation:)
          broadcaster.broadcast_settings_update

          label       = I18n.t("pito.slash.config.toggle.#{provider}.label")
          state_str   = I18n.t("pito.slash.config.toggle.state.#{bool ? 'on' : 'off'}")

          Pito::Slash::Result::Ok.new(events: [
            {
              kind:    "system",
              payload: {
                text: Pito::Copy.render(
                  "pito.slash.config.toggle.confirmed",
                  { label: label, state: state_str }
                )
              }
            }
          ])
        end

        def show_toggle_status(provider)
          enabled = provider == "sound" ? AppSetting.sound_enabled? : AppSetting.fx_enabled?
          label   = I18n.t("pito.slash.config.toggle.#{provider}.label")
          state   = I18n.t("pito.slash.config.toggle.state.#{enabled ? 'on' : 'off'}")

          Pito::Slash::Result::Ok.new(events: [
            {
              kind:    "system",
              payload: {
                text: Pito::Copy.render(
                  "pito.slash.config.toggle.status",
                  { label: label, state: state }
                )
              }
            }
          ])
        end

        # Returns true/false for accepted on/off synonyms; nil for unrecognised input.
        def parse_on_off(raw)
          case raw
          when "on",  "true",  "enable",  "enabled"  then true
          when "off", "false", "disable", "disabled" then false
          end
        end

        # True when the invocation targets the timezone provider, in either the
        # kv form (`timezone=Madrid`) or the bare form (`timezone [City]`).
        def timezone_command?
          invocation.kwargs.key?(:timezone) ||
            invocation.args.first.to_s.downcase == TIMEZONE_PROVIDER
        end

        # Handle /config timezone[=<City>]. No city → show the current zone.
        def handle_timezone
          city = timezone_value
          return show_timezone if city.blank?

          iana = resolve_timezone(city)
          if iana.nil?
            return Pito::Slash::Result::Error.new(
              message_key:  "pito.slash.config.errors.unknown_timezone",
              message_args: { city: city }
            )
          end

          AppSetting.timezone = iana

          Pito::Slash::Result::Ok.new(events: [
            {
              kind:    "system",
              payload: {
                text: Pito::Copy.render(
                  "pito.slash.config.timezone.updated",
                  { zone: iana }
                )
              }
            }
          ])
        end

        # The city the user supplied, from whichever form was used. nil/blank
        # for the bare getter `/config timezone`.
        def timezone_value
          return invocation.kwargs[:timezone].to_s.strip if invocation.kwargs.key?(:timezone)

          invocation.args[1].to_s.strip
        end

        # Resolves a major-city name (or IANA identifier) to its IANA identifier,
        # or nil when ActiveSupport::TimeZone cannot place it.
        def resolve_timezone(city)
          ActiveSupport::TimeZone[city.to_s.strip]&.tzinfo&.identifier
        end

        def show_timezone
          Pito::Slash::Result::Ok.new(events: [
            {
              kind:    "system",
              payload: {
                text: Pito::Copy.render(
                  "pito.slash.config.timezone.status",
                  { zone: AppSetting.timezone }
                )
              }
            }
          ])
        end

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

        # Returns the authoritative provider list, preferring the grammar registry
        # vocabulary when available and falling back to the combined list otherwise.
        def known_providers
          vocab = Pito::Grammar::Registry.vocabulary(:config_providers)
          vocab&.canonical || (KNOWN_PROVIDERS + TOGGLE_PROVIDERS)
        rescue StandardError
          KNOWN_PROVIDERS + TOGGLE_PROVIDERS
        end
      end
    end
  end
end
