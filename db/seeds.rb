# Seed data for development — run with: bin/rails db:seed
# Idempotent: safe to run multiple times.
#
# Phase 8 — Tenant Drop + Email-Only Login (ADR 0003). The seed reads
# `Rails.application.credentials.owner.{email, password}` only; there
# is no Tenant model, no `username`, no `tenant_name` / `tenant_slug`.

puts "seeding app settings..."
AppSetting.set("max_panes", "5")
AppSetting.set("pane_title_length", "14")
puts "  max_panes = 5, pane_title_length = 14"

# Phase 4 §3.5 (Phase B revamp, 2026-05-04) — Voyage AppSetting bootstrap.
# The key is sourced from Rails credentials during seeding so initial
# deployments work without manual UI entry. Once the app reaches Hetzner
# (Phase 16), credentials will hold the key only as a bootstrap fallback,
# and the UI becomes the authoritative source. Idempotent — re-running
# seeds does NOT clobber a key the user has already set, and the flag
# only flips on in production once the key is present.
if AppSetting.exists?
  setting = AppSetting.first
  if setting.voyage_api_key.blank?
    creds_key = Rails.application.credentials.dig(:voyage, Rails.env.to_sym, :api_key)
    if creds_key.present?
      setting.update!(voyage_api_key: creds_key)
      puts "  voyage_api_key seeded from credentials"
    end
  end
  if Rails.env.production? && setting.voyage_api_key.present? && !setting.voyage_index_project_notes
    setting.update!(voyage_index_project_notes: true)
    puts "  voyage_index_project_notes = true (production)"
  end
end

# ---------------------------------------------------------------------------
# Owner credentials (User)
# ---------------------------------------------------------------------------

owner_creds = Rails.application.credentials.dig(:owner)
if owner_creds.blank?
  puts "  WARNING: credentials :owner block missing; using placeholder values."
  puts "           run `bin/rails credentials:edit` to populate :owner with"
  puts "           email and password."
end

owner_email    = owner_creds&.dig(:email).presence || "owner@example.test"
owner_password = owner_creds&.dig(:password).presence || "change-me-please"

puts "seeding owner user..."
owner = User.find_or_initialize_by(email: owner_email)
owner.password = owner_password
owner.password_confirmation = owner_password
owner.save!
puts "  user: #{owner.email} (id=#{owner.id})"

# Phase 3 — Step C (5c-settings-ui-and-docs.md). Seed a default `dev` API
# token so the install ceremony captures plaintext once. Idempotent — second
# `db:seed` finds the existing row and is a no-op (the dev plaintext is gone
# forever after the first run; revoke + mint a new one if you lost it).
#
# Default scope set: dev:* + yt:* (read+write) + project:* (read+write). No
# `yt:destructive` by default — the user opts in by minting a separate token.
unless ApiToken.exists?(name: "dev")
  Current.user = owner
  pepper = Rails.application.credentials.dig(:tokens, :pepper)
  if pepper.blank?
    if Rails.env.development?
      # Local dev needs the pepper — halt with the helpful message so the
      # user knows exactly which credential to add and how to generate it.
      abort <<~MSG

        ERROR: cannot seed dev token — :tokens.pepper credential is missing.

        Run: bin/rails credentials:edit
        Add:
          tokens:
            pepper: <64-char hex>

        Generate a value with: openssl rand -hex 32
      MSG
    else
      # Test/CI/production-without-pepper: the dev token is a developer
      # convenience, not a runtime requirement. Skip and warn so seeds run
      # to completion (CI does not set master.key, by design).
      warn "  WARNING: :tokens.pepper missing; skipping dev token seed (#{Rails.env})."
    end
  else
    _token, plaintext = ApiToken.generate!(
      user:   owner,
      name:   "dev",
      scopes: [
        Scopes::DEV_READ, Scopes::DEV_WRITE,
        Scopes::YT_READ, Scopes::YT_WRITE,
        Scopes::PROJECT_READ, Scopes::PROJECT_WRITE
      ]
    )
    puts ""
    puts "=" * 64
    puts "Dev token minted (save this now — cannot be shown again):"
    puts plaintext
    puts "=" * 64
    puts ""
  end
end

# ---------------------------------------------------------------------------
# 100 channels with deterministic distribution
# ---------------------------------------------------------------------------

puts "seeding channels..."

# Phase 7 Path A2 (literal full retract). Seeded channels start with
# oauth_identity_id: nil — connection happens through /settings/youtube
# at runtime. We still seed a starred subset so the [starred] filter
# chip and "starred" column have something to show.
CHANNEL_SEED_COUNT = 100
STAR_COUNT = 7
URL_ALPHABET = ("A".."Z").to_a + ("a".."z").to_a + ("0".."9").to_a + %w[_ -]

rng = Random.new(42)

star_indexes = (0...STAR_COUNT).to_a # 0..6

day_seconds = 60 * 60 * 24
window = 60 * day_seconds

channel_ids = []
CHANNEL_SEED_COUNT.times do |i|
  suffix = Array.new(22) { URL_ALPHABET[rng.rand(URL_ALPHABET.length)] }.join
  url = "https://www.youtube.com/channel/UC#{suffix}"
  star = star_indexes.include?(i)
  created_offset = rng.rand(window)
  created_at = Time.current - created_offset

  ch = Channel.find_or_initialize_by(channel_url: url)
  ch.star = star
  ch.last_synced_at = nil
  ch.created_at = created_at if ch.new_record?
  ch.save!
  channel_ids << ch.id
end

puts "  #{channel_ids.length} channels seeded"
puts "    starred: #{Channel.where(star: true).count}"

puts "seeding videos..."

# ---------------------------------------------------------------------------
# Per-channel video generation. Phase 7 Path A2 (literal full retract):
# Video is a thin YouTube-reference record — only youtube_video_id +
# channel are seeded. No title/description/tags/etc.
# ---------------------------------------------------------------------------

video_count = 0

# Seed only the first 10 channels with stats data (keeps seed time
# reasonable while still exercising the rest of the pipeline).
seedable_channels = Channel.order(:id).limit(10)
seedable_channels.each_with_index do |channel, channel_idx|
  base_views = 500 + (channel.id * 137) % 6000
  growth = 1.0 + ((channel.id % 13) - 6) * 0.001
  count = 20

  count.times do |i|
    raw_id = "#{channel.channel_url[-10..]}#{channel_idx}#{i.to_s.rjust(3, '0')}"
    vid_id = raw_id.gsub(/[^A-Za-z0-9_-]/, "x")[0, 11]
    published = Time.zone.now - rand(5..365).days - rand(0..23).hours
    duration_seconds_local = rand(90..5400)

    video = Video.find_or_initialize_by(youtube_video_id: vid_id)
    video.assign_attributes(channel: channel)
    video.star = (i.zero?) if video.new_record?
    video.save!
    video_count += 1

    # Generate up to 90 days of stats with realistic trends.
    days_since_publish = (Date.current - published.to_date).to_i
    stat_days = [ days_since_publish, 90 ].min

    is_viral = rand < 0.1
    spike_day = rand(5..30) if is_viral

    stat_days.times do |d|
      date = Date.current - d.days
      days_old = (date - published.to_date).to_i.clamp(0, 999)

      decay = [ 1.0 / (1 + days_old * 0.06), 0.08 ].max
      trend = growth**(90 - d)
      weekend = date.on_weekend? ? 1.2 : 1.0
      spike = (is_viral && (days_old - spike_day).abs <= 2) ? rand(3.0..6.0) : 1.0

      views = (base_views * decay * trend * weekend * spike * (0.7 + rand * 0.6)).round.clamp(1, 999_999)
      likes = (views * rand(0.03..0.08)).round
      comments = (views * rand(0.005..0.02)).round
      shares = (views * rand(0.002..0.01)).round
      watch_time = (views * duration_seconds_local / 60.0 * rand(0.25..0.65)).round

      VideoStat.find_or_initialize_by(video: video, date: date).tap do |stat|
        stat.assign_attributes(views: views, likes: likes, comments: comments,
                               shares: shares, watch_time_minutes: watch_time)
        stat.save!
      end
    end
  end
end

puts "  #{video_count} videos with stats"

# ---------------------------------------------------------------------------
# Phase 4 — Project Workspace sample data
# ---------------------------------------------------------------------------
#
# Seeds one Collection, one Game (with cover art attached from
# spec/fixtures/files/cover_art.jpg), one Project that references the Game and
# the Collection, one Note (`last_modified_at` mirrors the row's creation), and
# one Timeline in the initial `editing` state. Idempotent — `find_or_*` calls
# guard against repeat runs.

puts "seeding project workspace sample..."

collection = Collection.find_or_create_by!(name: "Demo Collection")

game = Game.find_or_initialize_by(title: "Demo Game")
game.collection ||= collection
game.publisher  ||= "Demo Studios"
game.platforms = [ { "platform" => "PS5", "owned" => true, "recorded_on" => true } ] if game.platforms.blank?
game.save!

cover_fixture_path = Rails.root.join("spec/fixtures/files/cover_art.jpg")
if cover_fixture_path.exist? && !game.cover_art.attached?
  game.cover_art.attach(
    io: File.open(cover_fixture_path),
    filename: "cover_art.jpg",
    content_type: "image/jpeg"
  )
end

project = Project.find_or_create_by!(name: "Demo Project")

# Polymorphic references — Project -> Game and Project -> Collection.
ProjectReference.find_or_create_by!(
  project: project,
  referenceable_type: "Game", referenceable_id: game.id
)
ProjectReference.find_or_create_by!(
  project: project,
  referenceable_type: "Collection", referenceable_id: collection.id
)

# Sample Note — disk file is NOT created here (NoteSyncJob does that in
# Phase B). The DB row alone is enough for Phase A's smoke test.
Note.find_or_create_by!(
  project: project, path: "demo-note.md"
) do |note|
  note.title = "Demo note"
  note.last_modified_at = Time.current
end

# Sample Timeline in the initial state (aasm `editing`).
Timeline.find_or_create_by!(project: project, title: "Demo Timeline") do |t|
  t.state = :editing
end

puts "  1 collection, 1 game (with cover art), 1 project (2 references), 1 note, 1 timeline"

puts "done!"
