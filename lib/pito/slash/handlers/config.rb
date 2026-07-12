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
      # **Toggle provider** (`sound`):
      # - **Getter** (no arg): `/config sound` → current on/off state.
      # - **Setter**: `/config sound on|off` (synonyms: true/false/enable/disable/enabled/disabled)
      #   → writes via `AppSetting` and broadcasts a settings-update cable event.
      # - Invalid toggle value → `Result::Error` with key `pito.slash.config.errors.invalid_toggle_value`.
      #
      # (The `motion` toggle and `fx` reveal-effect provider were removed.)
      #
      # Bare `/config` (no provider) → general overview table of all providers.
      # Unknown provider → `Result::Error` with key `pito.slash.config.errors.unknown_provider`.
      #
      # Sensitive keys (`client_id`, `client_secret`, `api_key`) are masked to `***`
      # in the echo by `Pito::InputMasking.mask_config_credentials` *before* this handler runs.
      #
      # `show_help` is overridden: `/config --help` renders the general provider table;
      # `/config google --help` renders Google-specific key table with `/connect` suggestion.
      class Config < Pito::Slash::Handler
        self.tool = :config
        self.description_key = "pito.slash.config.descriptions.config"
        # Grammar (provider/state/settings slots, auth, aliases): config/pito/tools.yml.

        # Every AI provider in the registry gets a `/config <name> api_key=…`
        # entry (and a status getter) automatically — one YAML entry, full
        # config surface.
        KNOWN_PROVIDERS   = %w[ai tavily google voyage igdb webhook].freeze
        TOGGLE_PROVIDERS  = %w[sound].freeze
        # Maps each provider's supported kwargs to their AppSetting writers.
        # AI config has EXACTLY ONE slash surface — `/config ai` with kwargs
        # (owner-locked): `provider=` scopes the other kwargs, `api_key=` lands
        # in the encrypted store for that provider, `model=` must exist in that
        # provider's catalog and stamps the active pick + recents, `effort=`
        # binds to the ACTIVE model. NO per-provider slash commands, no AI
        # spillage into the /config overview. Bare `/config ai` never reaches
        # this handler — the web fast-path opens the picker overlay instead.
        PROVIDER_SETTERS = {
          # Keys only — the AI path routes through set_ai_values (ORDERED:
          # provider scopes, then key, then model, then effort), never these.
          "ai" => {
            provider: nil,
            api_key:  nil,
            model:    nil,
            effort:   nil
          },
          "google" => {
            client_id:     ->(v) { AppSetting.singleton_row.update!(google_oauth_client_id: v) },
            client_secret: ->(v) { AppSetting.singleton_row.update!(google_oauth_client_secret: v) },
            redirect_uri:  ->(v) { AppSetting.google_oauth_redirect_uri = v },
            api_key:       ->(v) { AppSetting.google_api_key = v }
          },
          # The @ai --web search backend (Tavily; P14).
          "tavily" => {
            api_key: ->(v) { AppSetting.set("tavily_api_key", v) }
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
          "ai" => -> {
            provider = AppSetting.get("ai_provider").presence || "opencode"
            model    = AppSetting.get("ai_model").presence
            {
              "Provider" => provider,
              "API Key"  => status_flag(AppSetting.get("#{provider}_api_key")),
              "Model"    => model || I18n.t("pito.slash.config.status.missing"),
              "Effort"   => (model && AppSetting.ai_effort_for("#{provider}/#{model}")).presence ||
                            I18n.t("pito.slash.config.status.missing")
            }
          },
          "google" => -> {
            {
              "Client ID"     => status_flag(Pito::Credentials.google_oauth_client_id),
              "Client Secret" => status_flag(Pito::Credentials.google_oauth_client_secret),
              "Redirect URI"  => status_flag(Pito::Credentials.google_oauth_redirect_uri),
              "API Key"       => status_flag(Pito::Credentials.google_api_key)
            }
          },
          "voyage" => -> {
            { "API Key" => status_flag(Pito::Credentials.voyage_api_key) }
          },
          "tavily" => -> {
            { "API Key" => status_flag(AppSetting.get("tavily_api_key")) }
          },
          "igdb" => -> {
            {
              "Client ID"     => status_flag(Pito::Credentials.igdb_client_id),
              "Client Secret" => status_flag(Pito::Credentials.igdb_client_secret)
            }
          },
          "webhook" => -> {
            {
              "Slack"   => status_flag(Pito::Credentials.slack_webhook_url),
              "Discord" => status_flag(Pito::Credentials.discord_webhook_url)
            }
          }
        }.freeze

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
          provider = invocation.args.first.to_s.downcase

          case provider
          when "google"   then google_help_man_page
          when "timezone" then timezone_help_man_page
          when ""         then general_help_man_page
          else                 provider_keys_help_man_page(provider)
          end
        end

        # Called for bare `/config` (no provider, no --help flag) as well as
        # from show_help when no provider is specified.
        def general_help_events
          general_help_man_page
        end

        private

        def general_help_man_page
          # Presentational grouping only (T10.57): the overview clusters
          # providers under titled sections, but every command stays
          # `/config <provider>`.
          provider_groups = Pito::Slash::HelpBuilder::CONFIG_PROVIDER_GROUPS.map do |group, providers|
            title = I18n.t("pito.slash.config.help.general.groups.#{group}")
            rows  = providers.map do |p|
              [ p, I18n.t("pito.slash.config.help.general.providers.#{p}", default: "") ]
            end
            [ title, rows ]
          end
          info_line = I18n.t("pito.slash.config.help.general.info_line")

          body = Pito::MessageBuilder::ManPage.render(
            usage:  I18n.t("pito.slash.config.help.general.body"),
            groups: provider_groups + [ [ "Options:", [ [ "--help", info_line ] ] ] ]
          )
          man_ok(body)
        end


        def google_help_man_page
          rows = [
            [ "client_id=",     I18n.t("pito.slash.config.help.providers.google.keys.client_id") ],
            [ "client_secret=", I18n.t("pito.slash.config.help.providers.google.keys.client_secret") ],
            [ "redirect_uri=",  I18n.t("pito.slash.config.help.providers.google.keys.redirect_uri") ],
            [ "api_key=",       I18n.t("pito.slash.config.help.providers.google.keys.api_key") ]
          ]
          connect_post = I18n.t("pito.slash.config.help.providers.google.suggestion.post")

          body = Pito::MessageBuilder::ManPage.render(
            usage:  "/config google [key=value …]",
            groups: [
              [ "Keys:",    rows ],
              [ "Options:", [
                [ "--help",   "Print this help message" ],
                [ "/connect", "Run /connect #{connect_post}" ]
              ] ]
            ]
          )
          man_ok(body)
        end

        def timezone_help_man_page
          desc = I18n.t("pito.slash.config.help.providers.timezone", default: "/config timezone <City>")
          body = Pito::MessageBuilder::ManPage.render(
            usage:  "/config timezone [<City>]",
            groups: [ [ "Options:", [ [ "--help", desc ] ] ] ]
          )
          man_ok(body)
        end

        def provider_keys_help_man_page(provider)
          keys = begin
            Pito::Grammar::Vocabularies.provider_keys(provider)
          rescue StandardError
            []
          end

          return general_help_man_page if keys.blank?

          rows = keys.map do |key|
            desc = I18n.t("pito.slash.config.help.providers.#{provider}.keys.#{key}", default: "")
            [ "#{key}=", desc ]
          end

          body = Pito::MessageBuilder::ManPage.render(
            usage:  "/config #{provider} [key=value …]",
            groups: [
              [ "Keys:",    rows ],
              [ "Options:", [ [ "--help", "Print this help message" ] ] ]
            ]
          )
          man_ok(body)
        end

        def man_ok(body)
          Pito::Slash::Result::Ok.new(events: [ {
            kind:    :system,
            payload: { "html" => true, "body" => body }
          } ])
        end


        # Handle /config sound [on|off].
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

          AppSetting.sound_enabled = bool

          broadcaster = Pito::Stream::Broadcaster.new(conversation:)
          broadcaster.broadcast_settings_update

          label       = I18n.t("pito.slash.config.toggle.#{provider}.label")
          state_str   = I18n.t("pito.slash.config.toggle.state.#{bool ? 'on' : 'off'}")

          Pito::Slash::Result::Ok.new(events: [
            {
              kind:    :system,
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
          enabled = AppSetting.sound_enabled?
          label   = I18n.t("pito.slash.config.toggle.#{provider}.label")
          state   = I18n.t("pito.slash.config.toggle.state.#{enabled ? 'on' : 'off'}")

          Pito::Slash::Result::Ok.new(events: [
            {
              kind:    :system,
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
              kind:    :system,
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
              kind:    :system,
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

          return set_ai_values(kwargs) if provider == "ai"

          kwargs.each { |key, value| setters[key.to_sym]&.call(value.to_s) }
          Pito::Credentials.invalidate!

          Pito::Slash::Result::Ok.new(events: [
            {
              kind:    :system,
              payload: {
                message_key:  "pito.slash.config.updated",
                message_args: { provider: provider, keys: kwargs.keys.map(&:to_s).join(", ") }
              }
            }
          ])
        end

        AI_EFFORTS = %w[low medium high off].freeze

        # The ONE slash surface for AI config (owner-locked): ordered kwargs —
        # `provider=` scopes the rest (defaults to the active provider),
        # `api_key=` lands in that provider's encrypted slot, `model=` is
        # catalog-validated and stamps the active pick + recents, `effort=`
        # binds to the ACTIVE model (per-model map). Everything else about AI
        # lives in the /config ai picker overlay.
        def set_ai_values(kwargs)
          kwargs = kwargs.transform_keys(&:to_sym)
          scope  = (kwargs[:provider].presence || AppSetting.get("ai_provider").presence || "opencode").to_s

          begin
            ::Ai::ProviderRegistry.provider(scope.to_sym)
          rescue KeyError
            return ai_error("unknown_provider", provider: scope)
          end

          AppSetting.set("#{scope}_api_key", kwargs[:api_key].to_s.strip) if kwargs[:api_key].present?

          if kwargs[:model].present?
            model = kwargs[:model].to_s
            known = ::Ai::ModelCatalog.models(provider: scope.to_sym).any? { |m| m[:id] == model }
            return ai_error("unknown_model", model: model, provider: scope) unless known

            AppSetting.set("ai_model", model)
            AppSetting.set("ai_provider", scope)
            AppSetting.push_ai_recent("#{scope}/#{model}")
          end

          if kwargs[:effort].present?
            effort = kwargs[:effort].to_s
            return ai_error("unknown_effort", effort: effort) unless AI_EFFORTS.include?(effort)

            active_model = AppSetting.get("ai_model").presence
            return ai_error("no_model") if active_model.nil?

            active_provider = AppSetting.get("ai_provider").presence || scope
            AppSetting.set_ai_effort("#{active_provider}/#{active_model}", effort)
          end

          Pito::Credentials.invalidate!

          Pito::Slash::Result::Ok.new(events: [
            {
              kind:    :system,
              payload: {
                message_key:  "pito.slash.config.updated",
                message_args: { provider: "ai", keys: kwargs.keys.map(&:to_s).join(", ") }
              }
            }
          ])
        end

        def ai_error(key, **args)
          Pito::Slash::Result::Error.new(
            message_key:  "pito.slash.config.errors.ai_#{key}",
            message_args: args
          )
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
