# Phase 29 (settings refactor) — install-level config rake tasks.
#
# Source of truth is `config/pito.yml` (gitignored). The initializer
# `config/initializers/pito_config.rb` loads it at boot. These tasks
# read + write the file directly (and remind the operator to restart
# Puma when a `set` lands).
#
# All tasks print to STDOUT, never STDERR (operator-facing tooling,
# not log output).
#
# Tasks:
#   bin/rails pito:config:show
#   bin/rails pito:config:max_panes:get
#   bin/rails pito:config:max_panes:set[N]
#   bin/rails pito:config:pane_title_length:get
#   bin/rails pito:config:pane_title_length:set[N]
#   bin/rails pito:config:timezone:get
#   bin/rails pito:config:timezone:set[IANA_NAME]
#
# Invalid values print a one-line error and exit non-zero so CI / shell
# pipelines can detect failures.

require "yaml"

PITO_CONFIG_PATH = Rails.root.join("config/pito.yml")

namespace :pito do
  namespace :config do
    desc "Show the install-level pito config (max_panes, pane_title_length, timezone)."
    task show: :environment do
      data = PitoConfigTaskHelpers.read_yaml
      puts "max_panes:         #{data['max_panes'] || Pito::Config::DEFAULTS['max_panes']} (default: #{Pito::Config::DEFAULTS['max_panes']})"
      puts "pane_title_length: #{data['pane_title_length'] || Pito::Config::DEFAULTS['pane_title_length']} (default: #{Pito::Config::DEFAULTS['pane_title_length']})"
      puts "timezone:          #{data['timezone'] || Pito::Config::DEFAULTS['timezone']} (default: #{Pito::Config::DEFAULTS['timezone']})"
      puts "source:            #{PITO_CONFIG_PATH}"
    end

    namespace :max_panes do
      desc "Print the current max_panes value."
      task get: :environment do
        puts PitoConfigTaskHelpers.read_yaml["max_panes"] || Pito::Config::DEFAULTS["max_panes"]
      end

      desc "Set max_panes to N (1..10). Usage: pito:config:max_panes:set[5]"
      task :set, [ :value ] => :environment do |_t, args|
        raw = args[:value].to_s
        if raw.strip.empty?
          puts "error: missing value. Usage: pito:config:max_panes:set[N]"
          exit 1
        end
        begin
          value = Integer(raw)
        rescue ArgumentError
          puts "error: #{raw.inspect} is not an integer."
          exit 1
        end
        unless Pito::Config::MAX_PANES_RANGE.cover?(value)
          puts "error: #{value} is out of range #{Pito::Config::MAX_PANES_RANGE}."
          exit 1
        end
        PitoConfigTaskHelpers.write_key("max_panes", value)
        puts "max_panes set to #{value}."
        puts PitoConfigTaskHelpers::RESTART_REMINDER
      end
    end

    namespace :pane_title_length do
      desc "Print the current pane_title_length value."
      task get: :environment do
        puts PitoConfigTaskHelpers.read_yaml["pane_title_length"] || Pito::Config::DEFAULTS["pane_title_length"]
      end

      desc "Set pane_title_length to N (6..50). Usage: pito:config:pane_title_length:set[18]"
      task :set, [ :value ] => :environment do |_t, args|
        raw = args[:value].to_s
        if raw.strip.empty?
          puts "error: missing value. Usage: pito:config:pane_title_length:set[N]"
          exit 1
        end
        begin
          value = Integer(raw)
        rescue ArgumentError
          puts "error: #{raw.inspect} is not an integer."
          exit 1
        end
        unless Pito::Config::PANE_TITLE_LENGTH_RANGE.cover?(value)
          puts "error: #{value} is out of range #{Pito::Config::PANE_TITLE_LENGTH_RANGE}."
          exit 1
        end
        PitoConfigTaskHelpers.write_key("pane_title_length", value)
        puts "pane_title_length set to #{value}."
        puts PitoConfigTaskHelpers::RESTART_REMINDER
      end
    end

    namespace :timezone do
      desc "Print the current install-level timezone."
      task get: :environment do
        puts PitoConfigTaskHelpers.read_yaml["timezone"] || Pito::Config::DEFAULTS["timezone"]
      end

      desc "Set install-level timezone to an IANA name. Usage: pito:config:timezone:set[Europe/Bucharest]"
      task :set, [ :value ] => :environment do |_t, args|
        raw = args[:value].to_s
        if raw.strip.empty?
          puts "error: missing value. Usage: pito:config:timezone:set[IANA_NAME]"
          exit 1
        end
        if ActiveSupport::TimeZone[raw].nil?
          puts "error: #{raw.inspect} is not a valid IANA timezone."
          exit 1
        end
        PitoConfigTaskHelpers.write_key("timezone", raw)
        puts "timezone set to #{raw}."
        puts PitoConfigTaskHelpers::RESTART_REMINDER
      end
    end
  end
end

# Internal helpers for the pito:config:* tasks. Read + write
# `config/pito.yml` preserving the existing key order.
module PitoConfigTaskHelpers
  RESTART_REMINDER = "(restart Puma to apply: tmux send-keys -t pito:rails C-c Enter)".freeze

  def self.read_yaml
    return {} unless File.exist?(PITO_CONFIG_PATH)
    YAML.safe_load_file(PITO_CONFIG_PATH) || {}
  rescue Psych::SyntaxError
    {}
  end

  def self.write_key(key, value)
    data = read_yaml
    data[key] = value
    # Preserve the canonical key order so the file stays readable.
    ordered = {}
    %w[max_panes pane_title_length timezone].each do |k|
      ordered[k] = data[k] if data.key?(k)
    end
    File.write(PITO_CONFIG_PATH, ordered.to_yaml)
  end
end
