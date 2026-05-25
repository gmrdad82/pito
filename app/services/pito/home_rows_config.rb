# Pito::HomeRowsConfig — value object for the home dashboard row configuration.
#
# Purpose:
#   Owns the canonical default layout, validates incoming row arrays, and
#   normalises missing optional fields before they reach the DB or renderer.
#
# Shape of a single row:
#   {
#     "cols"   => Integer (1..4),               # required — number of column slots
#     "panels" => Array,                         # required — one entry per slot
#     "ratios" => Array<Integer> (optional)      # column widths; must sum to 100
#   }
#
# A "panels" entry is either:
#   - A String key from ALLOWED_PANEL_KEYS   → simple panel
#   - A Hash `{ "stack" => [<keys>] }`       → vertical stack of panels in that slot
#
# Public API:
#   Pito::HomeRowsConfig.default          → Array (3-row factory default)
#   Pito::HomeRowsConfig.validate!(arr)   → raises ArgumentError on bad shape
#   Pito::HomeRowsConfig.normalize(arr)   → returns normalized copy (fills ratios)
#
# Related:
#   AppSetting#home_rows_config            — instance reader (JSON → Array)
#   AppSetting#home_rows_config=           — instance writer (Array → JSON, validates)
#   AppSetting.home_rows_config            — class-level singleton accessor
#   AppSetting.set_home_rows!(arr)         — class-level singleton writer

module Pito
  module HomeRowsConfig
    # All panel keys that may appear in a row definition.
    # Extend this list as new panels are added to the home screen.
    ALLOWED_PANEL_KEYS = %w[
      games_releasing
      notifications_feed
      calendar
      stack
      notifications
      security
      notifications_panel
      security_panel
    ].freeze

    # The factory-default 3-row home layout.
    # Mirrors the DEFAULT_HOME_ROWS constant in the migration.
    def self.default
      [
        { "cols" => 1, "panels" => [ "games_releasing" ] },
        { "cols" => 2, "panels" => [ "notifications_feed", "calendar" ], "ratios" => [ 40, 60 ] },
        {
          "cols" => 2,
          "panels" => [ "stack", { "stack" => [ "notifications", "security" ] } ],
          "ratios" => [ 60, 40 ]
        }
      ]
    end

    # Validates arr against the expected shape.
    # Raises ArgumentError with a descriptive message on the first violation.
    def self.validate!(arr)
      raise ArgumentError, "home_rows must be an Array, got #{arr.class}" unless arr.is_a?(Array)

      arr.each_with_index do |row, idx|
        prefix = "home_rows[#{idx}]"

        cols = row["cols"]
        raise ArgumentError, "#{prefix}: 'cols' must be an Integer" unless cols.is_a?(Integer)
        raise ArgumentError, "#{prefix}: 'cols' must be between 1 and 4, got #{cols}" unless (1..4).cover?(cols)

        panels = row["panels"]
        raise ArgumentError, "#{prefix}: 'panels' must be an Array" unless panels.is_a?(Array)
        unless panels.length == cols
          raise ArgumentError,
                "#{prefix}: 'panels' length (#{panels.length}) must match 'cols' (#{cols})"
        end

        panels.each_with_index do |slot, slot_idx|
          validate_slot!(slot, "#{prefix}[panels][#{slot_idx}]")
        end

        next unless row.key?("ratios")

        ratios = row["ratios"]
        raise ArgumentError, "#{prefix}: 'ratios' must be an Array" unless ratios.is_a?(Array)
        unless ratios.length == cols
          raise ArgumentError,
                "#{prefix}: 'ratios' length (#{ratios.length}) must match 'cols' (#{cols})"
        end
        total = ratios.sum
        unless total == 100
          raise ArgumentError, "#{prefix}: 'ratios' must sum to 100, got #{total}"
        end
      end

      arr
    end

    # Returns a normalised deep copy of arr.
    # Currently fills missing 'ratios' with equal-width values.
    def self.normalize(arr)
      arr.map do |row|
        row = row.dup
        unless row.key?("ratios")
          cols = row["cols"].to_i
          equal_share = (100.0 / cols).floor
          remainder   = 100 - (equal_share * cols)
          ratios      = Array.new(cols, equal_share)
          ratios[-1] += remainder if cols > 0
          row["ratios"] = ratios
        end
        row
      end
    end

    # -- private -----------------------------------------------------------------

    def self.validate_slot!(slot, path)
      if slot.is_a?(String)
        unless ALLOWED_PANEL_KEYS.include?(slot)
          raise ArgumentError, "#{path}: unknown panel key #{slot.inspect}. " \
                               "Allowed: #{ALLOWED_PANEL_KEYS.join(', ')}"
        end
      elsif slot.is_a?(Hash)
        keys = slot.keys
        unless keys == [ "stack" ]
          raise ArgumentError,
                "#{path}: nested slot Hash must have exactly one key 'stack', got #{keys.inspect}"
        end
        sub = slot["stack"]
        raise ArgumentError, "#{path}[stack]: must be an Array" unless sub.is_a?(Array)
        sub.each_with_index { |key, i| validate_slot!(key, "#{path}[stack][#{i}]") }
      else
        raise ArgumentError, "#{path}: slot must be a String or Hash, got #{slot.class}"
      end
    end
    private_class_method :validate_slot!
  end
end
