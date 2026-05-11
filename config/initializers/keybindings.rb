# Loads the unified keybindings schema (`config/keybindings.yml`)
# into `Rails.application.config.keybindings` so layout helpers /
# Stimulus controllers can read it without re-parsing on every
# request. The CLI (extras/cli/) reads the same file via serde_yaml;
# both stacks share the YAML on disk as the source of truth.
#
# The schema is treated as an immutable hash — callers are expected
# to mutate copies. Rendering pipelines that emit JSON for the front
# end go through `KeybindingsHelper#keybindings_as_json`.
#
# Loaded eagerly at boot so the absence of the file (or a YAML parse
# error) surfaces immediately rather than on first request. In test /
# CI the same path is exercised — the file is part of the repo and
# always present.
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
schema = YAML.safe_load_file(path, permitted_classes: [ Symbol ])
Rails.application.config.keybindings = deep_freeze.call(schema)
