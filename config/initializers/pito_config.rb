# Phase 29 (settings refactor) — install-level Pito config loader.
#
# Reads `config/pito.yml` (gitignored, per-install) at boot and exposes
# the three operator-level workspace knobs on
# `Rails.application.config.x.pito.<key>`:
#
#   - `max_panes` (Integer, 1..10) — workspace pane cap.
#   - `pane_title_length` (Integer, 6..50) — pane title truncation.
#   - `timezone` (String, IANA name) — install-level timezone used by
#     calendar / games / milestone rules.
#
# Theme is intentionally NOT loaded here — it moved to localStorage
# only (no server-side persistence) as part of the settings refactor.
#
# Missing file or missing keys fall back to safe defaults so a
# greenfield install boots cleanly. Invalid values fall back to the
# default and log a warning (we never raise at boot — that would
# brick `bin/rails`).
#
# Changes to `config/pito.yml` require a Puma restart to take effect.

module Pito
  module Config
    DEFAULTS = {
      "max_panes"         => 3,
      "pane_title_length" => 14,
      "timezone"          => "UTC"
    }.freeze

    MAX_PANES_RANGE         = (1..10).freeze
    PANE_TITLE_LENGTH_RANGE = (6..50).freeze

    PATH = Rails.root.join("config/pito.yml")

    # Returns a hash with the three load-validated values. Missing or
    # invalid entries fall back to DEFAULTS. Public so the rake tasks
    # can read the live values without touching `config.x.pito`
    # (which is frozen during normal request flow).
    def self.load!
      raw =
        if File.exist?(PATH)
          begin
            YAML.safe_load_file(PATH) || {}
          rescue Psych::SyntaxError => e
            warn "[pito_config] failed to parse #{PATH}: #{e.message}. Using defaults."
            {}
          end
        else
          {}
        end

      raw = raw.transform_keys(&:to_s)

      {
        "max_panes"         => integer_in_range(raw["max_panes"], DEFAULTS["max_panes"], MAX_PANES_RANGE, "max_panes"),
        "pane_title_length" => integer_in_range(raw["pane_title_length"], DEFAULTS["pane_title_length"], PANE_TITLE_LENGTH_RANGE, "pane_title_length"),
        "timezone"          => valid_timezone(raw["timezone"], DEFAULTS["timezone"])
      }
    end

    def self.integer_in_range(raw_value, default, range, key)
      return default if raw_value.nil?
      value = Integer(raw_value)
      return value if range.cover?(value)
      warn "[pito_config] #{key}=#{value.inspect} is out of range #{range}. Using default #{default}."
      default
    rescue ArgumentError, TypeError
      warn "[pito_config] #{key}=#{raw_value.inspect} is not an integer. Using default #{default}."
      default
    end

    def self.valid_timezone(raw_value, default)
      return default if raw_value.nil?
      value = raw_value.to_s
      return value if ActiveSupport::TimeZone[value].present?
      warn "[pito_config] timezone=#{value.inspect} is not a valid IANA name. Using default #{default}."
      default
    end
  end
end

Rails.application.config.x.pito = ActiveSupport::OrderedOptions.new
loaded = Pito::Config.load!
Rails.application.config.x.pito.max_panes         = loaded["max_panes"]
Rails.application.config.x.pito.pane_title_length = loaded["pane_title_length"]
Rails.application.config.x.pito.timezone          = loaded["timezone"]
