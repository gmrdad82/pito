# frozen_string_literal: true

module Ai
  # Cached loader + validator for config/pito/ai_providers.yml.
  #
  # Declares HOW to reach each AI provider (wire format, host, auth style,
  # model discovery) — WHICH provider/model is active, and the API keys, live
  # in AppSetting (set through `/config ai`). Loads + deep-freezes the YAML
  # once per boot; memoized at the module level, mirroring the loading
  # conventions of Pito::Dispatch::Config. Validation runs on first access, so
  # a typo in the file fails loudly at boot/spec time, never silently at call
  # time.
  #
  # Public API:
  #   Ai::ProviderRegistry.providers           # => { opencode: { frozen descriptor }, … }
  #   Ai::ProviderRegistry.provider(:opencode)  # => frozen descriptor Hash (KeyError if unknown)
  #   Ai::ProviderRegistry.provider_names       # => [ :opencode ]
  #   Ai::ProviderRegistry.reload!              # clears memoization (used in dev + tests)
  module ProviderRegistry
    # Raised when config/pito/ai_providers.yml fails schema validation.
    class InvalidConfig < StandardError; end

    PATH = Rails.root.join("config/pito/ai_providers.yml")

    SCHEMA_VERSION    = 1
    TOP_LEVEL_KEYS    = %i[schema_version providers].freeze
    PROVIDER_KEYS     = %i[label wire base_url auth models_endpoint capabilities pinned_models].freeze
    CAPABILITY_KEYS   = %i[streaming reasoning].freeze
    ALLOWED_WIRE      = %w[openai_chat anthropic_messages].freeze
    ALLOWED_AUTH      = %w[bearer x_api_key].freeze
    ALLOWED_REASONING = %w[none effort budget passthrough].freeze

    module_function

    # Returns the frozen provider Hash, symbol-keyed by provider name.
    def providers
      data.fetch(:providers)
    end

    # Returns the frozen descriptor Hash for +name+ (String or Symbol).
    # Raises KeyError for an unknown provider.
    def provider(name)
      providers.fetch(name.to_sym) do
        raise KeyError, "Ai::ProviderRegistry: unknown provider #{name.inspect}"
      end
    end

    # Returns the declared provider names as an Array of Symbols.
    def provider_names
      providers.keys
    end

    # Clears memoization so the next access reloads + revalidates from disk.
    def reload!
      @data = nil
    end

    # Returns the memoized, deep-frozen, schema-validated parsed YAML document.
    def data
      @data ||= load!
    end

    # ── Private ───────────────────────────────────────────────────────────────

    def load!
      invalid!("", "file not found") unless PATH.exist?

      raw = YAML.safe_load_file(PATH, symbolize_names: true)
      validate_top_level!(raw)
      deep_freeze(raw)
    end

    def validate_top_level!(raw)
      check_keys!(raw, TOP_LEVEL_KEYS, path: "")

      unless raw[:schema_version] == SCHEMA_VERSION
        invalid!("schema_version", "must be #{SCHEMA_VERSION}, got #{raw[:schema_version].inspect}")
      end

      providers_data = raw[:providers]
      invalid!("providers", "must be a Hash, got #{providers_data.class}") unless providers_data.is_a?(Hash)

      providers_data.each { |name, descriptor| validate_provider!(name, descriptor) }
    end

    def validate_provider!(name, descriptor)
      path = "providers.#{name}"
      invalid!(path, "must be a Hash, got #{descriptor.class}") unless descriptor.is_a?(Hash)

      check_keys!(descriptor, PROVIDER_KEYS, path: path)

      unless descriptor[:label].is_a?(String)
        invalid!("#{path}.label", "must be a String, got #{descriptor[:label].inspect}")
      end

      unless ALLOWED_WIRE.include?(descriptor[:wire])
        invalid!("#{path}.wire", "must be one of #{ALLOWED_WIRE.inspect}, got #{descriptor[:wire].inspect}")
      end

      base_url = descriptor[:base_url]
      unless base_url.is_a?(String) && base_url.start_with?("https://")
        invalid!("#{path}.base_url", "must be a https:// String, got #{base_url.inspect}")
      end

      unless ALLOWED_AUTH.include?(descriptor[:auth])
        invalid!("#{path}.auth", "must be one of #{ALLOWED_AUTH.inspect}, got #{descriptor[:auth].inspect}")
      end

      models_endpoint = descriptor[:models_endpoint]
      unless models_endpoint.is_a?(String) && models_endpoint.start_with?("/")
        invalid!("#{path}.models_endpoint", "must be a String starting with \"/\", got #{models_endpoint.inspect}")
      end

      validate_capabilities!(descriptor[:capabilities], path: path)
      validate_pinned_models!(descriptor[:pinned_models], path: path)
    end

    def validate_capabilities!(capabilities, path:)
      cap_path = "#{path}.capabilities"
      invalid!(cap_path, "must be a Hash, got #{capabilities.class}") unless capabilities.is_a?(Hash)

      check_keys!(capabilities, CAPABILITY_KEYS, path: cap_path)

      unless [ true, false ].include?(capabilities[:streaming])
        invalid!("#{cap_path}.streaming", "must be true/false, got #{capabilities[:streaming].inspect}")
      end

      return if ALLOWED_REASONING.include?(capabilities[:reasoning])

      invalid!("#{cap_path}.reasoning",
                "must be one of #{ALLOWED_REASONING.inspect}, got #{capabilities[:reasoning].inspect}")
    end

    def validate_pinned_models!(pinned_models, path:)
      full_path = "#{path}.pinned_models"
      return if pinned_models.is_a?(Array) && pinned_models.all? { |m| m.is_a?(String) }

      invalid!(full_path, "must be an Array of Strings, got #{pinned_models.inspect}")
    end

    # Raises unless +hash+'s keys are exactly +allowed+ (no unknown, none
    # missing) — +optional+ keys may be present but are never required.
    def check_keys!(hash, allowed, path:, optional: [])
      extra = hash.keys - allowed - optional
      invalid!(path, "unknown key(s) #{extra.inspect} (allowed: #{(allowed + optional).inspect})") unless extra.empty?

      missing = allowed - hash.keys
      return if missing.empty?

      invalid!(path, "missing key(s) #{missing.inspect} (allowed: #{(allowed + optional).inspect})")
    end

    # Builds the InvalidConfig message, naming the offending dotted path (or
    # the bare file path for document-level failures).
    def invalid!(path, message)
      prefix = path.to_s.empty? ? PATH.to_s : "#{PATH} #{path}"
      raise InvalidConfig, "#{prefix}: #{message}"
    end

    def deep_freeze(obj)
      case obj
      when Hash  then obj.transform_values { |v| deep_freeze(v) }.freeze
      when Array then obj.map { |v| deep_freeze(v) }.freeze
      else            obj.frozen? ? obj : obj.freeze
      end
    end
  end
end
