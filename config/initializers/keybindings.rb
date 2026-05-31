# Loads the unified keybindings schema (`config/keybindings.yml`)
# into `Rails.application.config.keybindings` so layout helpers /
# Stimulus controllers can read it without re-parsing on every
# request. The YAML on disk is the source of truth.
#
# The schema is treated as an immutable hash — callers are expected
# to mutate copies. Rendering pipelines that emit JSON for the front
# end go through `KeybindingsHelper#keybindings_as_json`.
#
# Loaded eagerly at boot so the absence of the file (or a YAML parse
# error) surfaces immediately rather than on first request. In test /
# CI the same path is exercised — the file is part of the repo and
# always present.
#
# Development override: instead of a frozen hash, we store a Proc that
# re-parses the YAML on every call. `KeybindingsHelper` invokes the
# Proc when present so YAML edits become visible on browser refresh
# without restarting `bin/dev`. Production + test keep the boot-time
# freeze for perf + immutability — the dev branch is the only one that
# pays the per-request parse cost.
require "yaml"

# Recursively deep-freeze a hash / array tree so the config is
# unmutable for the lifetime of the process. The standard library
# `Object#freeze` is shallow; the config is nested 3 levels deep
# (top-level, `menus`, per-menu `items` array, item hash) so a manual
# walk is the simplest way to guarantee no caller can mutate it.
deep_freeze = ->(obj) {
  case obj
  when Hash
    obj.each_value { |v| deep_freeze.call(v) }
  when Array
    obj.each { |v| deep_freeze.call(v) }
  end
  obj.freeze
}

path = Rails.root.join("config", "keybindings.yml")

# Lightweight shape validator. Confirms the top-level sections we know
# about have the right shape, but tolerates missing/empty blocks so a
# half-populated schema (e.g. `modal_actions:` waiting on Phase B)
# does not crash boot.
#
# Known sections:
#   leader:         { key:, display: }
#   page_actions:   { <page_key> => [item, ...], ... }
#   modal_actions:  { <modal_key> => { items: [item, ...] }, ... }  (A2)
#   menus:          { <menu_name> => { items: [item, ...] }, ... }
#
# Anything not matching is logged at warn level rather than raised —
# the YAML is parseable, so the app boots; the warn surfaces the
# typo in dev where it matters.
validate_keybindings = ->(schema) {
  return unless schema.is_a?(Hash)
  modal_actions = schema["modal_actions"]
  if modal_actions && !modal_actions.is_a?(Hash)
    Rails.logger.warn("[keybindings] `modal_actions` should be a Hash, got #{modal_actions.class}")
    return
  end
  (modal_actions || {}).each do |modal_key, entry|
    unless entry.is_a?(Hash)
      Rails.logger.warn("[keybindings] `modal_actions[#{modal_key}]` should be a Hash, got #{entry.class}")
      next
    end
    items = entry["items"]
    next if items.nil? # empty stub is fine
    unless items.is_a?(Array)
      Rails.logger.warn("[keybindings] `modal_actions[#{modal_key}].items` should be an Array, got #{items.class}")
    end
  end
}

if Rails.env.development?
  # Dev: store a fresh-read Proc so each browser refresh sees the
  # latest YAML on disk. No freeze — the returned hash is a brand-new
  # parse, so accidental mutation by a caller dies with the request.
  # Parse once at boot to fail fast on syntax errors; then swap in the
  # Proc for runtime use.
  boot_schema = YAML.safe_load_file(path, permitted_classes: [ Symbol ])
  validate_keybindings.call(boot_schema)
  Rails.application.config.keybindings = -> {
    schema = YAML.safe_load_file(path, permitted_classes: [ Symbol ])
    validate_keybindings.call(schema)
    schema
  }
else
  schema = YAML.safe_load_file(path, permitted_classes: [ Symbol ])
  validate_keybindings.call(schema)
  Rails.application.config.keybindings = deep_freeze.call(schema)
end
