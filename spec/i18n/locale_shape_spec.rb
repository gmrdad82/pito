require "rails_helper"

# Guards the shape of the project-scoped i18n surface.
#
# Two directions, both can fail silently without this spec:
#
#   Direction 1 — every static `t("...")` / `I18n.t("...")` call (and every
#     `label_i18n: ...` reference in `config/keybindings.yml`) resolves to
#     an actual YAML key.
#   Direction 2 — every YAML key defined under the project-scoped locale
#     trees is referenced by at least one in-scope code site.
#
# Scope (both directions):
#   Code           — app/views/**/*.erb, app/components/**/*.{rb,erb},
#                    app/helpers/**/*.rb, app/controllers/**/*.rb,
#                    app/models/**/*.rb
#   Schema         — config/keybindings.yml (the `label_i18n:` references)
#   Locale YAML    — config/locales/{games,settings,bundles,common,keybindings}/**/*.yml
#
# Out of scope:
#   - Rails-default / shared-infra keys (activerecord.*, errors.*, date.*,
#     time.*, number.*, datetime.*, helpers.*, support.*) — allowlisted.
#   - Doorkeeper / devise / other gem locales — `config/locales/doorkeeper.en.yml`
#     and `config/locales/en.yml` are not walked.
#   - Dynamic key construction (`t("foo.#{var}.bar")`) — the extractor can't
#     statically resolve these, so they are skipped (not flagged either way).
#   - Relative t-calls (`t(".title")`) — these resolve via the controller /
#     view path at runtime and are skipped.
#
# Failure output is aggregated into a single readable list per direction —
# never one failure per missing key. Fix-it dispatches read the list and
# patch in one pass.
RSpec.describe "locale shape guard" do
  # ---------- Configuration -------------------------------------------------

  CODE_GLOBS = %w[
    app/views/**/*.erb
    app/components/**/*.rb
    app/components/**/*.erb
    app/helpers/**/*.rb
    app/controllers/**/*.rb
    app/models/**/*.rb
  ].freeze

  LOCALE_GLOBS = %w[
    config/locales/games/**/*.yml
    config/locales/settings/**/*.yml
    config/locales/bundles/**/*.yml
    config/locales/common/**/*.yml
    config/locales/keybindings/**/*.yml
  ].freeze

  KEYBINDINGS_SCHEMA_FILE = "config/keybindings.yml".freeze

  # Top-level locale prefixes that Rails / Rails-defaults / gems own. Keys
  # under these prefixes are NOT flagged as orphans even if no project code
  # references them — they're consumed by framework internals.
  ALLOWLISTED_KEY_PREFIXES = %w[
    activerecord.
    activemodel.
    errors.
    date.
    time.
    number.
    datetime.
    helpers.
    support.
  ].freeze

  # ---------- Extractors ----------------------------------------------------

  # Matches `t("foo.bar")`, `t('foo.bar')`, `I18n.t("foo.bar")`, `I18n.t('foo.bar')`.
  # The negative lookbehind on the t() form rejects identifier suffixes like
  # `format(` / `last(` / `helpers.t(` (helpers.t is still caught — `helpers.`
  # is a method chain, not a word-boundary t). The first char inside the
  # quotes must be a word char so relative `.title` keys are skipped.
  T_CALL_PATTERN = /
    (?:                                # one of:
      \bI18n\.t\(                      #   I18n.t(
      |
      (?<![A-Za-z0-9_])t\(             #   t(   — word-boundary on the t
    )
    \s*
    ["']                               # opening quote
    (?<key>[A-Za-z][\w]*(?:\.[\w]+)+)  # dotted key, must start with a letter,
                                       # must contain at least one dot
    ["']                               # closing quote
  /x

  # Matches `label_i18n: keybindings.foo.bar` in config/keybindings.yml.
  # The value can be bare or quoted.
  LABEL_I18N_PATTERN = /\blabel_i18n:\s*["']?(?<key>[A-Za-z][\w]*(?:\.[\w]+)+)["']?/

  # Matches a dynamic-key t-call: `t("foo.bar.#{var}")` /
  # `I18n.t("foo.bar.#{var}.baz")`. We capture the dotted PREFIX up to
  # (and including) the dot immediately before the interpolation hole so
  # any defined key under that prefix can be treated as "referenced".
  # Example: `t("settings.notification_toggle.brand.#{brand}")` yields
  # the prefix `settings.notification_toggle.brand.` — matching any of
  # `settings.notification_toggle.brand.discord` /
  # `settings.notification_toggle.brand.slack` as references.
  DYNAMIC_KEY_PATTERN = /
    (?:\bI18n\.t\(|(?<![A-Za-z0-9_])t\()
    \s*
    ["']
    (?<prefix>[A-Za-z][\w]*(?:\.[\w]+)*\.)   # dotted prefix ending in '.'
    \#\{                                     # then a Ruby interpolation hole
  /x

  # Helper: flatten a nested hash into dotted key paths. Pluralization
  # leaves (`one:` / `other:` / `zero:` / `few:` / `many:`) are folded
  # into the parent key — callers treat the parent as "the key" because
  # that's what `I18n.t(key, count: ...)` resolves against.
  PLURAL_LEAVES = %w[one other zero few many].to_set.freeze

  def self.flatten_keys(hash, prefix = nil, out = [])
    hash.each do |k, v|
      key = prefix ? "#{prefix}.#{k}" : k.to_s
      if v.is_a?(Hash)
        plural_only = v.keys.map(&:to_s).all? { |sub| PLURAL_LEAVES.include?(sub) }
        if plural_only
          # Treat the parent as the leaf key — pluralization sub-keys
          # (one / other) are picked by I18n at render time when `count:`
          # is passed. Flagging `noun.one` as an orphan because the call
          # site only references `noun` would be a false positive.
          out << key
        else
          flatten_keys(v, key, out)
        end
      else
        out << key
      end
    end
    out
  end

  # ---------- Data load (memoized via let_it_be–style ||=) ------------------

  def code_file_paths
    @code_file_paths ||= CODE_GLOBS.flat_map { |g| Dir.glob(Rails.root.join(g).to_s) }.uniq.sort
  end

  def locale_file_paths
    @locale_file_paths ||= LOCALE_GLOBS.flat_map { |g| Dir.glob(Rails.root.join(g).to_s) }.uniq.sort
  end

  def keybindings_schema_path
    Rails.root.join(KEYBINDINGS_SCHEMA_FILE).to_s
  end

  # All static t-keys referenced by the in-scope code.
  def referenced_keys_from_code
    keys = []
    code_file_paths.each do |path|
      contents = File.read(path)
      contents.scan(T_CALL_PATTERN) { keys << Regexp.last_match[:key] }
    end
    if File.exist?(keybindings_schema_path)
      File.read(keybindings_schema_path).scan(LABEL_I18N_PATTERN) do
        keys << Regexp.last_match[:key]
      end
    end
    keys.uniq.sort
  end

  # All keys defined in the in-scope locale YAMLs. Returned as dotted
  # strings without the `en.` root prefix — call sites do not include the
  # locale prefix.
  def defined_keys_from_locales
    keys = []
    locale_file_paths.each do |path|
      data = YAML.load_file(path)
      next unless data.is_a?(Hash)
      # Locale files are rooted at `en:`; strip the locale prefix.
      data.each do |locale, tree|
        next unless tree.is_a?(Hash)
        self.class.flatten_keys(tree, nil, keys)
        # Ignore `locale` itself in output, but reference it to silence
        # unused-block-arg linters in case rubocop ever runs on this file.
        _ = locale
      end
    end
    keys.uniq.sort
  end

  # Plain-string search: does any in-scope code file mention the literal
  # key string? Includes the keybindings schema (so `label_i18n:` refs
  # count as references for orphan-detection purposes).
  def all_searchable_text
    @all_searchable_text ||= begin
      blobs = code_file_paths.map { |p| File.read(p) }
      blobs << File.read(keybindings_schema_path) if File.exist?(keybindings_schema_path)
      blobs.join("\n")
    end
  end

  # All dotted PREFIXES from dynamic-key t-calls. Any defined key that
  # starts with one of these prefixes counts as referenced — the actual
  # leaf was assembled at runtime via `#{var}` and can't be statically
  # extracted. Example: `t("platforms.chip.label.#{slug}")` yields the
  # prefix `platforms.chip.label.` and covers `.ps` / `.switch` / `.steam`.
  def dynamic_key_prefixes
    @dynamic_key_prefixes ||= begin
      prefixes = []
      code_file_paths.each do |path|
        File.read(path).scan(DYNAMIC_KEY_PATTERN) do
          prefixes << Regexp.last_match[:prefix]
        end
      end
      prefixes.uniq.sort
    end
  end

  # ---------- Specs ---------------------------------------------------------

  it "every static t-key referenced in code resolves to a defined locale key" do
    referenced = referenced_keys_from_code
    expect(referenced).not_to be_empty,
      "Extractor found zero t-keys — the regex or the code glob is broken."

    missing = referenced.reject do |key|
      begin
        I18n.t(key, raise: true)
        true
      rescue I18n::MissingTranslationData
        false
      end
    end

    expect(missing).to be_empty,
      "Found #{missing.size} t-key reference(s) in code with no matching " \
      "YAML entry. Add the keys to config/locales/<area>/ or remove the " \
      "stale references:\n" + missing.sort.join("\n")
  end

  it "every defined locale key under the in-scope trees is referenced" do
    defined = defined_keys_from_locales
    expect(defined).not_to be_empty,
      "Locale flattener returned zero keys — the YAML walker or the glob is broken."

    text = all_searchable_text
    dynamic_prefixes = dynamic_key_prefixes

    orphans = defined.reject do |key|
      next true if ALLOWLISTED_KEY_PREFIXES.any? { |prefix| key.start_with?(prefix) }
      next true if dynamic_prefixes.any? { |prefix| key.start_with?(prefix) }
      # A key is "referenced" if its dotted form appears anywhere in the
      # in-scope code or in the keybindings schema. Substring match is
      # acceptable for now — keys are dotted, namespaced, and unlikely
      # to collide with unrelated text.
      text.include?(key)
    end

    expect(orphans).to be_empty,
      "Found #{orphans.size} orphan locale key(s) — defined under " \
      "config/locales/{games,settings,bundles,common,keybindings} but not " \
      "referenced by any in-scope code site or by config/keybindings.yml. " \
      "Remove the entries from the YAML or wire up the missing call site:\n" +
      orphans.sort.join("\n")
  end
end
