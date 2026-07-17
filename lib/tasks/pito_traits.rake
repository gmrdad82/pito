# frozen_string_literal: true

# The game-trait classify round-trip (traits-design.md section 6) plus the
# derivation backfill/heal task (section 5):
#
#   rake pito:traits:derive           # recompute every derived tag from
#                                      # synced IGDB data (idempotent, heals
#                                      # stale tags, prints changed/errors)
#   rake pito:traits:export           # write every game to a reviewable
#                                      # YAML file for a Claude classify pass
#   rake pito:traits:import           # validate + apply a reviewed file
#
#   TRAITS_FILE=<path>  overrides the default tmp/traits_classify.yml for
#                        both export and import.
#
#   rake pito:nightly                 # on-demand convenience alias for the
#                                      # full NightlyReindexJob heal (traits
#                                      # derive -> NL corpus sync -> embeddings
#                                      # reindex) — see below.
#
# No top-level app-constant references outside method/task bodies below —
# `Rails.application.load_tasks` evaluates every `.rake` file's top-level
# code BEFORE the `:environment` task runs (before Zeitwerk autoloading is
# available), so a bare `Game::Traits::Vocabulary` reference outside a
# `def ... end` / `task ... do ... end` body would raise `NameError` on
# EVERY rake invocation (`rake -T` included) — the same load-order lesson
# `lib/tasks/pito_images.rake` and `lib/tasks/pito_nl.rake` already document.
# Every method below is safe: a `def` body is compiled, not executed, at
# load time — only actually CALLING one (which only happens inside a task
# body, after `:environment` has loaded) touches Zeitwerk.

def pito_traits_file_path
  ENV["TRAITS_FILE"].presence || Rails.root.join("tmp/traits_classify.yml").to_s
end

# Pins every scalar written into the classify YAML through ONE formatter —
# safe for a bare title with a colon/quote in it, invisible (bare word) for
# the vast majority of scale values / titles that need no escaping at all.
def pito_traits_yq(value)
  Psych.dump(value, line_width: -1).delete_prefix("--- ").chomp
end

# ── Derive ───────────────────────────────────────────────────────────────

def pito_traits_derive_all!
  changed = unchanged = errors = 0

  Game.find_each do |game|
    result = Game::Traits::Derive.call(game)
    result[:changed] ? changed += 1 : unchanged += 1
  rescue StandardError => e
    errors += 1
    msg = "  game ##{game.id} FAILED: #{e.class}: #{e.message}"
    puts msg
    Rails.logger.warn(msg)
  end

  { changed: changed, unchanged: unchanged, errors: errors }
end

# ── Export ───────────────────────────────────────────────────────────────

def pito_traits_export_header
  scales_doc = Game::Traits::Vocabulary.scale_names.map do |name|
    meta = Game::Traits::Vocabulary.scales[name]
    "#   #{name}: #{meta['values'].join(' | ')} — #{meta['description']}"
  end.join("\n")

  tags_doc = Game::Traits::Vocabulary.classified_tag_names.map do |name|
    "#   #{name} — #{Game::Traits::Vocabulary.tags[name]['description']}"
  end.join("\n")

  derived_doc = Game::Traits::Vocabulary.derived_tag_names.sort.join(", ")

  <<~HEADER
    # PITO game-trait classify file — self-contained protocol (any Claude
    # session can fill this with zero extra context beyond this file).
    #
    # For each game below, fill every BLANK scale/tag slot judging from the
    # per-game facts comment (igdb / score / ttb / summary) plus your own
    # knowledge of the game. Leave a slot BLANK when genuinely unjudgeable —
    # never guess just to fill every field.
    #
    # Scales (write at most one value per game, exactly as listed; blank = unset):
    #{scales_doc}
    #
    # Classifiable tags (write into that game's `tags:` array; never invent
    # a new name; never write a derived tag here — see below):
    #{tags_doc}
    #
    # Derived tags (computed automatically by `rake pito:traits:derive` from
    # already-synced IGDB data): #{derived_doc}
    # These NEVER belong at the top level — the importer rejects them there.
    # The owner may still pin one, per game, via that game's `overrides:`
    # block below (see the syntax after the example).
    #
    # The owner may edit ANYTHING in this file after Claude fills it. A value
    # the owner wants LOCKED FOREVER — never overwritten by a future classify
    # import or by derivation — belongs in that game's `overrides:` block
    # instead of (or in addition to) the top-level slot:
    #
    #   overrides:
    #     difficulty: brutal        # pins a scale value
    #     tags: [space, "!awful"]   # pins "space" present, "awful" absent
    #
    # A leading "!" on a tag name inside `overrides.tags` pins that tag
    # ABSENT forever — MUST be quoted ("!awful", not !awful) or the YAML
    # parser reads it as a tag directive and the file fails to load. Derived
    # tag names are legal ONLY inside `overrides:`. An empty `overrides: {}`
    # is a no-op — any existing owner pins persist untouched either way.
    #
    # Re-running `rake pito:traits:export` regenerates this file from the
    # current DB state (classified + owner values only — derived tags never
    # appear here) — always safe to re-export after an import lands.

    games:
  HEADER
end

def pito_traits_export_facts(game)
  return [ "# igdb — not synced" ] unless game.igdb_synced_at

  lines = [ pito_traits_export_igdb_line(game), pito_traits_export_meta_line(game),
            pito_traits_export_score_line(game), pito_traits_export_ttb_line(game) ].compact
  lines + pito_traits_export_summary_lines(game)
end

def pito_traits_export_igdb_line(game)
  bits = []
  bits << "genres: #{game.genres.map(&:name).join(', ')}" if game.genres.any?
  bits << "themes: #{game.themes.join(', ')}" if game.themes.any?
  "# igdb — #{bits.join(' · ')}" if bits.any?
end

def pito_traits_export_meta_line(game)
  bits = []
  bits << "perspectives: #{game.player_perspectives.join(', ')}" if game.player_perspectives.any?
  bits << "platforms: #{game.platforms.join(', ')}" if game.platforms.any?
  bits << "released: #{game.release_year || 'TBA'}"
  "# #{bits.join(' · ')}"
end

def pito_traits_export_score_line(game)
  bits = []
  bits << "igdb #{game.igdb_rating.to_i}/#{game.igdb_rating_count}" if game.igdb_rating.present?
  bits << "critics #{game.aggregated_rating.to_i}/#{game.aggregated_rating_count}" if game.aggregated_rating.present?
  bits << "total #{game.total_rating.to_i}/#{game.total_rating_count}" if game.total_rating.present?
  "# score: #{game.score} (#{bits.join(' · ')})" if game.score.present? && bits.any?
end

def pito_traits_export_ttb_line(game)
  bits = []
  bits << "main #{game.ttb_main_seconds / 3600}h" if game.ttb_main_seconds.to_i.positive?
  bits << "extras #{game.ttb_extras_seconds / 3600}h" if game.ttb_extras_seconds.to_i.positive?
  bits << "completionist #{game.ttb_completionist_seconds / 3600}h" if game.ttb_completionist_seconds.to_i.positive?
  "# ttb — #{bits.join(' · ')}" if bits.any?
end

def pito_traits_export_summary_lines(game)
  return [] if game.summary.blank?

  wrapped = game.summary.strip.truncate(400).scan(/.{1,68}(?:\s|\z)/).map(&:strip).reject(&:blank?)
  return [] if wrapped.empty?

  [ "# summary: #{wrapped.first}" ] + wrapped[1..].map { |l| "#   #{l}" }
end

def pito_traits_export_scale_line(game, name)
  meta = Game::Traits::Vocabulary.scales[name]
  # Derived-declared scales (none exist today, but stay future-proof) never
  # prefill — same "never derived" rule as tags.
  value = meta["source"] == "derived" ? nil : game.trait_value(name)
  rendered = value.nil? ? "" : " #{pito_traits_yq(value)}"
  "    #{name}:#{rendered} # #{meta['values'].join(' | ')}"
end

def pito_traits_export_game_yaml(game)
  lines = [ "  - id: #{game.id}", "    title: #{pito_traits_yq(game.title)}" ]
  lines.concat(pito_traits_export_facts(game).map { |l| "    #{l}" })
  lines.concat(Game::Traits::Vocabulary.scale_names.map { |name| pito_traits_export_scale_line(game, name) })

  tags = game.trait_tags & Game::Traits::Vocabulary.classified_tag_names
  lines << "    tags: [#{tags.join(', ')}] # classifiable tag names only (never derived), see header"
  lines << "    overrides: {}"
  lines.join("\n")
end

def pito_traits_export!(path)
  games = Game.order(:id).to_a
  body = pito_traits_export_header + games.map { |g| pito_traits_export_game_yaml(g) }.join("\n\n") + "\n"
  File.write(path, body)
  games.size
end

# ── Import ───────────────────────────────────────────────────────────────

def pito_traits_allowed_game_keys
  %w[id title] + Game::Traits::Vocabulary.scale_names + %w[tags overrides]
end

def pito_traits_import_validate(data)
  result = { errors: [], warnings: [] }
  unless data.is_a?(Hash) && data["games"].is_a?(Array)
    result[:errors] << "file must be a Hash with a top-level \"games:\" Array"
    return result
  end

  games = data["games"]
  dup_ids = games.filter_map { |g| g["id"] if g.is_a?(Hash) }.tally.select { |_id, n| n > 1 }.keys
  result[:errors] << "duplicate id(s): #{dup_ids.sort.inspect}" if dup_ids.any?

  games.each { |entry| pito_traits_import_validate_entry(entry, result) }
  result
end

def pito_traits_import_validate_entry(entry, result)
  unless entry.is_a?(Hash) && entry["id"].is_a?(Integer)
    result[:errors] << "entry missing a valid integer id: #{entry.inspect}"
    return
  end

  id = entry["id"]
  game = Game.find_by(id: id)
  unless game
    result[:errors] << "game ##{id}: unknown id (no such game)"
    return
  end

  if entry["title"].present? && entry["title"].to_s != game.title
    result[:warnings] << "game ##{id}: title mismatch (file #{entry['title'].inspect} vs db #{game.title.inspect}) — id wins"
  end

  unknown_keys = entry.keys - pito_traits_allowed_game_keys
  result[:errors] << "game ##{id}: unknown key(s) #{unknown_keys.sort.inspect}" if unknown_keys.any?

  pito_traits_import_validate_scales(id, entry, result)
  pito_traits_import_validate_tags(id, entry, result)
  pito_traits_import_validate_overrides(id, entry, result)
end

def pito_traits_import_validate_scales(id, entry, result)
  Game::Traits::Vocabulary.scale_names.each do |name|
    next unless entry.key?(name)

    value = entry[name]
    next if value.nil? || Game::Traits::Vocabulary.valid_scale_value?(name, value)

    result[:errors] << "game ##{id}: #{value.inspect} is not a valid value for scale #{name.inspect} " \
      "(allowed: #{Game::Traits::Vocabulary.scales[name]['values'].inspect})"
  end
end

def pito_traits_import_validate_tags(id, entry, result)
  return unless entry.key?("tags")

  unless entry["tags"].is_a?(Array)
    result[:errors] << "game ##{id}: tags must be an Array"
    return
  end

  entry["tags"].each do |raw|
    tag = raw.to_s
    if tag.start_with?("!")
      result[:errors] << "game ##{id}: \"#{tag}\" pin-absent syntax is only legal inside overrides.tags"
    elsif Game::Traits::Vocabulary.derived_tag_names.include?(tag)
      result[:errors] << "game ##{id}: derived tag #{tag.inspect} is not legal at the top level (only inside overrides:)"
    elsif !Game::Traits::Vocabulary.tag_names.include?(tag)
      result[:errors] << "game ##{id}: unknown tag #{tag.inspect}"
    end
  end
end

def pito_traits_import_validate_overrides(id, entry, result)
  return unless entry.key?("overrides")

  overrides = entry["overrides"]
  unless overrides.is_a?(Hash)
    result[:errors] << "game ##{id}: overrides must be a Hash"
    return
  end

  pito_traits_import_validate_override_scales(id, overrides, result)
  pito_traits_import_validate_override_tags(id, overrides, result)
end

def pito_traits_import_validate_override_scales(id, overrides, result)
  overrides.except("tags").each do |key, value|
    unless Game::Traits::Vocabulary.scale_names.include?(key)
      result[:errors] << "game ##{id}: overrides has unknown key #{key.inspect}"
      next
    end
    next if value.nil? || Game::Traits::Vocabulary.valid_scale_value?(key, value)

    result[:errors] << "game ##{id}: overrides.#{key} #{value.inspect} is not a valid value " \
      "(allowed: #{Game::Traits::Vocabulary.scales[key]['values'].inspect})"
  end
end

def pito_traits_import_validate_override_tags(id, overrides, result)
  return unless overrides.key?("tags")

  unless overrides["tags"].is_a?(Array)
    result[:errors] << "game ##{id}: overrides.tags must be an Array"
    return
  end

  overrides["tags"].each do |raw|
    tag = raw.to_s.delete_prefix("!")
    result[:errors] << "game ##{id}: overrides.tags has unknown tag #{tag.inspect}" unless Game::Traits::Vocabulary.tag_names.include?(tag)
  end
end

def pito_traits_import_apply(games)
  totals = { games_touched: 0, values_set: 0, values_removed: 0, skipped_owner: 0, errors: 0 }

  games.each do |entry|
    pito_traits_import_apply_game(entry, totals)
  rescue StandardError => e
    totals[:errors] += 1
    msg = "  game ##{entry['id']} FAILED to apply: #{e.class}: #{e.message}"
    puts msg
    Rails.logger.warn(msg)
  end

  totals
end

def pito_traits_import_apply_game(entry, totals)
  game = Game.find_by(id: entry["id"])
  return unless game # already validated to exist; defensive only

  scales = Game::Traits::Vocabulary.scale_names.index_with { |name| entry[name] }
  add_tags = Array(entry["tags"]).map(&:to_s)
  currently_classifiable = game.trait_tags & Game::Traits::Vocabulary.classified_tag_names
  remove_tags = currently_classifiable - add_tags

  overrides = entry["overrides"].is_a?(Hash) ? entry["overrides"] : {}
  override_scales = overrides.except("tags")
  override_raw_tags = Array(overrides["tags"]).map(&:to_s)
  override_add = override_raw_tags.reject { |t| t.start_with?("!") }
  override_remove = override_raw_tags.select { |t| t.start_with?("!") }.map { |t| t.delete_prefix("!") }

  before_scales, before_tags = game.trait_scales, game.trait_tags

  classified_result = Game::Traits::Apply.call(
    game: game, source: "classified", scales: scales, add_tags: add_tags, remove_tags: remove_tags
  )
  owner_result = Game::Traits::Apply.call(
    game: game, source: "owner", scales: override_scales, add_tags: override_add, remove_tags: override_remove
  )

  pito_traits_tally!(totals, before_scales, before_tags, game.trait_scales, game.trait_tags,
                      classified_result, owner_result)
end

def pito_traits_tally!(totals, before_scales, before_tags, after_scales, after_tags, classified_result, owner_result)
  totals[:values_set] += (after_scales.to_a - before_scales.to_a).size + (after_tags - before_tags).size
  totals[:values_removed] += (before_scales.to_a - after_scales.to_a).size + (before_tags - after_tags).size
  totals[:skipped_owner] += classified_result[:skipped_owner].size + owner_result[:skipped_owner].size
  totals[:games_touched] += 1 if classified_result[:changed] || owner_result[:changed]
end

namespace :pito do
  namespace :traits do
    desc "Recompute derived game traits from synced IGDB data (idempotent; heals stale derived tags)"
    task derive: :environment do
      result = pito_traits_derive_all!
      puts "Derive: #{result[:changed]} changed, #{result[:unchanged]} unchanged, " \
        "#{result[:errors]} errors (#{result[:changed] + result[:unchanged] + result[:errors]} total)"
    end

    desc "Export every game to a reviewable classify YAML (TRAITS_FILE=<path>, default tmp/traits_classify.yml)"
    task export: :environment do
      path = pito_traits_file_path
      count = pito_traits_export!(path)
      puts "Exported #{count} games to #{path}"
    end

    desc "Validate + import a reviewed classify YAML (TRAITS_FILE=<path>, default tmp/traits_classify.yml)"
    task import: :environment do
      path = pito_traits_file_path
      abort "pito:traits:import: #{path} not found. Run pito:traits:export first." unless File.exist?(path)

      data = YAML.safe_load_file(path, aliases: false)
      validation = pito_traits_import_validate(data)

      if validation[:errors].any?
        abort(([ "Validation FAILED — nothing written:" ] + validation[:errors].map { |e| "  #{e}" }).join("\n"))
      end

      validation[:warnings].each { |w| puts "WARNING: #{w}" }

      totals = pito_traits_import_apply(data["games"])

      puts ""
      puts "Games touched:   #{totals[:games_touched]}"
      puts "Games unchanged: #{data['games'].size - totals[:games_touched] - totals[:errors]}"
      puts "Values set:      #{totals[:values_set]}"
      puts "Values removed:  #{totals[:values_removed]}"
      puts "Owner keeps:     #{totals[:skipped_owner]} (untouched owner-pinned name(s), skipped by design)"
      puts "Row errors:      #{totals[:errors]}"
      puts "Re-embeds for every touched game are enqueued via GameEmbedIndexJob (digest-gated)."
    end
  end

  # On-demand convenience alias for NightlyReindexJob's own heal order
  # (derive_traits -> sync_nl_examples -> games/videos/events reindex, see
  # the job's header comment) — composed from the three existing tasks that
  # already implement each phase (Rake::Task#invoke, not duplicated logic)
  # so this can never drift out of sync with any one of them. Note
  # pito:embeddings:reindex requires PITO_EMBEDDER_URL (see
  # lib/tasks/pito_embeddings.rake) and aborts without it — the nightly
  # job's own per-record fan-out is more forgiving (each indexer no-ops
  # instead of aborting), so an operator running this by hand for the full
  # synchronous sweep must have the embedder sidecar up first.
  desc "Run the full nightly heal on demand (traits derive -> NL corpus sync -> embeddings reindex)"
  task nightly: :environment do
    Rake::Task["pito:traits:derive"].invoke
    Rake::Task["pito:nl:sync"].invoke
    Rake::Task["pito:embeddings:reindex"].invoke
  end
end
