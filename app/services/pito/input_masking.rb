# frozen_string_literal: true

module Pito
  # Shared secret-masking for user input that is persisted, echoed, or recalled
  # in command history. `/config` credential kwarg VALUES and `/login` codes must
  # never surface in the echo OR the up/down recall history. This is the single
  # home for the masking rules — used by ChatController (echo) and
  # Turn#display_text (recall history). Credential KEY names live canonically in
  # Pito::Grammar::Vocabularies::MASKED_CONFIG_KEYS.
  module InputMasking
    module_function

    # The /config providers that carry secrets → routed SYNCHRONOUSLY so the raw
    # value is applied in-request and never persisted, and ALL their kwarg values
    # are masked everywhere they surface (echo, stored turn, logs). Other providers
    # (me, sound, motion, fx, timezone) carry no secret and stay on the async path
    # with their values shown in the clear.
    # AI keys travel ONLY through `/config ai api_key=…` — the per-provider
    # slash forms are gone, so `ai` is the only AI entry here.
    CREDENTIAL_PROVIDERS = %w[ai google voyage igdb webhook].freeze

    # `/config …` (verb-bounded, any case).
    def config_command?(input)
      input.to_s.strip.match?(%r{\A/config(\s|\z)}i)
    end

    # `/config google|voyage|igdb|webhook …` — the credential-bearing form whose
    # first arg names a secret provider. (`--help` is filtered out upstream by the
    # controller's help_flag? guard, so it still routes async.)
    def config_credential_command?(input)
      return false unless config_command?(input)

      provider = input.to_s.strip.split(/\s+/)[1]&.downcase
      CREDENTIAL_PROVIDERS.include?(provider)
    end

    # `/login …` or its `/authenticate` alias (verb-bounded, any case). Both route
    # to the synchronous login handler and both have their code masked in history.
    def login_command?(input)
      input.to_s.strip.match?(%r{\A/(?:login|authenticate)(\s|\z)}i)
    end

    # Mask EVERY kwarg value of a credential /config command to "***" (the whole
    # value after each `key=`). Applies ONLY to the credential providers
    # (google/voyage/igdb/webhook) — so google's redirect_uri and webhook's
    # slack/discord URLs are masked too, with one uniform rule — and is a no-op for
    # every other input (non-credential /config, chat, hashtags). Example:
    #   /config google client_id=abc client_secret=xyz redirect_uri=http://… api_key=k
    # → /config google client_id=*** client_secret=*** redirect_uri=*** api_key=***
    #   /config webhook slack=https://hooks.slack.com/…  →  /config webhook slack=***
    def mask_config_credentials(input)
      return input.to_s unless config_credential_command?(input)

      input.to_s.gsub(/(?<==)\S+/, "***")
    end

    # Mask everything after the verb (the entire secret payload), e.g.
    #   /login 123456 → /login ******
    def mask_secret(input)
      verb, rest = input.to_s.strip.split(/\s+/, 2)
      return input.to_s if rest.blank?

      "#{verb} #{'*' * rest.length}"
    end

    # The form safe to persist/recall in history: `/config` credentials masked,
    # `/login` payloads fully masked, everything else verbatim.
    def for_history(input)
      return mask_config_credentials(input) if config_command?(input)
      return mask_secret(input) if login_command?(input)

      input.to_s
    end
  end
end
