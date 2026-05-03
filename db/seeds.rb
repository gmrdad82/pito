# Seed data for development — run with: bin/rails db:seed
# Idempotent: safe to run multiple times

puts "seeding app settings..."
AppSetting.set("max_panes", "5")
AppSetting.set("pane_title_length", "14")
puts "  max_panes = 5, pane_title_length = 14"

# ---------------------------------------------------------------------------
# Owner credentials (Tenant + User)
# ---------------------------------------------------------------------------

owner_creds = Rails.application.credentials.dig(:owner)
if owner_creds.blank?
  puts "  WARNING: credentials :owner block missing; using placeholder values."
  puts "           run `bin/rails credentials:edit` to populate :owner with"
  puts "           tenant_name, username, email, password."
end

tenant_name = owner_creds&.dig(:tenant_name) || "Primary"
owner_username = owner_creds&.dig(:username) || "owner"
owner_email = owner_creds&.dig(:email) || "owner@example.test"
owner_password = owner_creds&.dig(:password) || "change-me"

puts "seeding tenant..."
tenant = Tenant.find_or_initialize_by(name: tenant_name)
tenant.save!
puts "  tenant: #{tenant.name} (id=#{tenant.id})"

puts "seeding owner user..."
owner = User.find_by(username: owner_username) || User.find_by(email: owner_email) || User.new
owner.tenant = tenant
owner.username = owner_username
owner.email = owner_email
owner.password = owner_password
owner.password_confirmation = owner_password
owner.save!
puts "  user: #{owner.username} <#{owner.email}> (id=#{owner.id})"

# ---------------------------------------------------------------------------
# 100 channels with deterministic distribution
# ---------------------------------------------------------------------------

puts "seeding channels..."

CHANNEL_SEED_COUNT = 100
STAR_COUNT = 7
CONNECTED_COUNT = 6
INTERSECTION_COUNT = 2
URL_ALPHABET = ("A".."Z").to_a + ("a".."z").to_a + ("0".."9").to_a + %w[_ -]

rng = Random.new(42)

# Indexes 0..1 are both starred AND connected.
# Indexes 2..6 are starred only (5 more, total 7 starred).
# Indexes 7..10 are connected only (4 more, total 6 connected).
# Indexes 11..99 are plain.
star_indexes      = (0...STAR_COUNT).to_a                                 # 0..6
connected_indexes = (0...INTERSECTION_COUNT).to_a +
                    (STAR_COUNT...(STAR_COUNT + CONNECTED_COUNT - INTERSECTION_COUNT)).to_a # 0,1 + 7..10

day_seconds = 60 * 60 * 24
window = 60 * day_seconds

channel_ids = []
CHANNEL_SEED_COUNT.times do |i|
  suffix = Array.new(22) { URL_ALPHABET[rng.rand(URL_ALPHABET.length)] }.join
  url = "https://www.youtube.com/channel/UC#{suffix}"
  star = star_indexes.include?(i)
  connected = connected_indexes.include?(i)
  created_offset = rng.rand(window)
  created_at = Time.current - created_offset

  ch = Channel.find_or_initialize_by(channel_url: url)
  ch.tenant = tenant
  ch.star = star
  ch.connected = connected
  ch.syncing = false
  ch.last_synced_at = nil
  ch.created_at = created_at if ch.new_record?
  ch.save!
  channel_ids << ch.id
end

puts "  #{channel_ids.length} channels seeded"
puts "    starred:           #{Channel.where(star: true).count}"
puts "    connected:         #{Channel.where(connected: true).count}"
puts "    starred+connected: #{Channel.where(star: true, connected: true).count}"

puts "seeding videos..."

# ---------------------------------------------------------------------------
# Per-channel video generation (uses Channel.id rotation in place of title)
# ---------------------------------------------------------------------------

title_template_groups = [
  [
    -> { "why I #{%w[switched stopped started tried].sample} #{%w[using building shipping testing].sample} #{%w[rails react postgres redis docker kubernetes].sample}" },
    -> { "#{%w[weekly daily].sample} #{%w[update recap vlog].sample} — #{(Date.current - rand(1..90)).strftime('%b %d')}" },
    -> { "honest take: #{%w[remote\ work burnout side\ projects freelancing open\ source].sample} in #{%w[2025 2026].sample}" }
  ],
  [
    -> { "how to #{%w[build deploy test debug refactor optimize].sample} #{%w[rails\ apps APIs background\ jobs webhooks auth\ systems].sample}" },
    -> { "#{%w[ruby rails hotwire turbo stimulus sidekiq].sample} #{%w[crash\ course deep\ dive walkthrough tutorial].sample}" },
    -> { "the truth about #{%w[microservices monoliths serverless GraphQL REST].sample}" }
  ],
  [
    -> { "#{%w[massive huge record-breaking].sample} #{%w[update announcement launch rebrand].sample} — what it means" },
    -> { "I analyzed #{rand(100..1000)} #{%w[channels videos creators thumbnails].sample} — here's what works" }
  ],
  [
    -> { "#{%w[perfect ultimate foolproof scientific].sample} #{%w[sourdough ramen steak pasta pizza risotto tacos].sample} #{%w[recipe technique method].sample}" },
    -> { "I #{%w[tried tested perfected].sample} #{%w[Gordon\ Ramsay's Kenji's Babish's].sample} #{%w[recipe technique method].sample}" },
    -> { "sous vide #{%w[chicken beef pork salmon eggs].sample} — #{%w[temperature time science].sample} explained" }
  ],
  [
    -> { "#{%w[hiking trail\ running backpacking climbing].sample} #{%w[the\ Alps Patagonia the\ Dolomites Yosemite the\ PCT].sample}" },
    -> { "#{%w[solo winter night sunrise].sample} #{%w[hike camp trek climb].sample} — #{%w[epic brutal peaceful stunning].sample} views" }
  ],
  [
    -> { "#{%w[retro indie hidden\ gem underrated classic].sample} #{%w[game review playthrough analysis].sample}: #{%w[Celeste Hades Stardew\ Valley Hollow\ Knight Balatro].sample}" },
    -> { "I played #{%w[the\ worst the\ best every a\ random].sample} #{%w[NES SNES N64 PS1 GameBoy].sample} game" }
  ],
  [
    -> { "#{%w[mixing mastering recording producing].sample} #{%w[vocals drums bass guitars synths].sample} — #{%w[tips mistakes workflow].sample}" },
    -> { "how to get a #{%w[professional radio-ready punchy warm clean].sample} #{%w[mix master sound vocal\ tone].sample}" }
  ],
  [
    -> { "#{%w[squat deadlift bench\ press overhead\ press pull-up].sample} #{%w[form guide technique mistakes science].sample}" },
    -> { "I tried #{%w[carnivore keto fasting bulking cutting].sample} for #{rand(2..12)} #{%w[weeks months days].sample}" }
  ],
  [
    -> { "#{%w[Tokyo Lisbon Istanbul Bangkok Marrakech Seoul Oaxaca].sample} #{%w[city\ guide travel\ vlog food\ tour photo\ walk].sample}" },
    -> { "#{%w[best hidden secret].sample} #{%w[spots cafes views neighborhoods markets].sample} in #{%w[Paris Berlin Barcelona Prague Vienna].sample}" }
  ],
  [
    -> { "building a #{%w[desk shelf cabinet workbench speaker guitar].sample} from #{%w[scratch walnut plywood reclaimed\ wood].sample}" },
    -> { "3D printing #{%w[tips failures upgrades mods enclosure].sample} — #{%w[Prusa Bambu Ender Voron].sample}" }
  ]
]

privacy_statuses = %w[public_video public_video public_video public_video public_video unlisted private_video]
default_languages = %w[en en en es fr de pt ja]
common_tags = %w[tutorial vlog tech music outdoor gaming cooking fitness travel diy]

video_count = 0

# Seed only the first 10 channels with rich video data (keeps seed time reasonable
# while still exercising the rest of the pipeline).
seedable_channels = Channel.order(:id).limit(10)
seedable_channels.each_with_index do |channel, channel_idx|
  templates = title_template_groups[channel.id % title_template_groups.length]
  base_views = 500 + (channel.id * 137) % 6000
  growth = 1.0 + ((channel.id % 13) - 6) * 0.001
  count = channel.connected? ? 30 : 20

  count.times do |i|
    raw_id = "#{channel.channel_url[-10..]}#{channel_idx}#{i.to_s.rjust(3, '0')}"
    vid_id = raw_id.gsub(/[^A-Za-z0-9_-]/, "x")[0, 11]
    published = Time.zone.now - rand(5..365).days - rand(0..23).hours
    title = templates.sample.call

    video = Video.find_or_initialize_by(youtube_video_id: vid_id)
    video.assign_attributes(
      channel: channel,
      title: title,
      description: "#{title}. published #{published.strftime('%Y-%m-%d')}.",
      published_at: published,
      duration_seconds: rand(90..5400),
      thumbnail_url: "https://i.ytimg.com/vi/#{vid_id}/hqdefault.jpg",
      tags: common_tags.sample(rand(2..5)),
      privacy_status: privacy_statuses.sample,
      category_id: [ 10, 17, 19, 20, 22, 24, 26, 28 ].sample,
      default_language: default_languages.sample,
      made_for_kids: false
    )
    video.save!
    video_count += 1

    # Generate up to 90 days of stats with realistic trends
    days_since_publish = (Date.current - video.published_at.to_date).to_i
    stat_days = [ days_since_publish, 90 ].min

    is_viral = rand < 0.1
    spike_day = rand(5..30) if is_viral

    stat_days.times do |d|
      date = Date.current - d.days
      days_old = (date - video.published_at.to_date).to_i.clamp(0, 999)

      decay = [ 1.0 / (1 + days_old * 0.06), 0.08 ].max
      trend = growth**(90 - d)
      weekend = date.on_weekend? ? 1.2 : 1.0
      spike = (is_viral && (days_old - spike_day).abs <= 2) ? rand(3.0..6.0) : 1.0

      views = (base_views * decay * trend * weekend * spike * (0.7 + rand * 0.6)).round.clamp(1, 999_999)
      likes = (views * rand(0.03..0.08)).round
      comments = (views * rand(0.005..0.02)).round
      shares = (views * rand(0.002..0.01)).round
      watch_time = (views * video.duration_seconds / 60.0 * rand(0.25..0.65)).round

      VideoStat.find_or_initialize_by(video: video, date: date).tap do |stat|
        stat.assign_attributes(views: views, likes: likes, comments: comments,
                               shares: shares, watch_time_minutes: watch_time)
        stat.save!
      end
    end
  end
end

puts "  #{video_count} videos with stats"
puts "done!"
