# Seed data for development — run with: bin/rails db:seed
# Idempotent: safe to run multiple times

puts "seeding app settings..."
AppSetting.set("max_panes", "5")
AppSetting.set("pane_title_length", "14")
puts "  max_panes = 5, pane_title_length = 14"

puts "seeding channels..."

channels_data = [
  { youtube_channel_id: "UCdQHEqTAcFEt5tEaYdTwrMg", title: "daily drive", connected: true,
    description: "daily vlogs, tech reviews, and random thoughts", subscriber_count: 45_200,
    video_count: 312, view_count: 8_750_000, base_views: 2000, growth: 1.005 },
  { youtube_channel_id: "UCxR2Z4N5vLcq3CEBU0kDfhQ", title: "code kitchen", connected: true,
    description: "ruby, rails, and web dev tutorials", subscriber_count: 12_800,
    video_count: 98, view_count: 2_100_000, base_views: 400, growth: 1.0 },
  { youtube_channel_id: "UC3pF7kAhLm9QnTCgbJ4dkWg", title: "competitor watch", connected: false,
    description: "a channel I'm keeping an eye on", subscriber_count: 890_000,
    video_count: 1_245, view_count: 120_000_000, base_views: 8000, growth: 0.997 },
  { youtube_channel_id: "UC7mK1Nv8Q2b5rLcFVx9pKTg", title: "pixel plates", connected: true,
    description: "cooking tutorials with a tech twist — sous vide, precision baking, fermentation logs",
    subscriber_count: 67_300, video_count: 245, view_count: 14_200_000,
    base_views: 3500, growth: 1.008 },
  { youtube_channel_id: "UC9fP2xN4vRk8JqLm3TzWeBg", title: "summit sessions", connected: true,
    description: "hiking, trail running, and outdoor adventures filmed in 4K",
    subscriber_count: 23_100, video_count: 156, view_count: 5_400_000,
    base_views: 1200, growth: 1.003 },
  { youtube_channel_id: "UCaB3dK7wLpR5vN6tYhMcXQg", title: "neon arcade", connected: false,
    description: "retro gaming, indie reviews, and game dev diaries",
    subscriber_count: 156_000, video_count: 520, view_count: 38_000_000,
    base_views: 5000, growth: 0.999 },
  { youtube_channel_id: "UCeF4hR9pLwN2vK3tJxMbYQg", title: "sound lab", connected: true,
    description: "music production, mixing tutorials, and gear reviews",
    subscriber_count: 34_500, video_count: 178, view_count: 7_800_000,
    base_views: 1800, growth: 1.002 },
  { youtube_channel_id: "UCgH2jK5mNpR8vT4wLxQbFQg", title: "iron protocol", connected: true,
    description: "strength training, nutrition science, and recovery protocols",
    subscriber_count: 98_200, video_count: 340, view_count: 22_500_000,
    base_views: 4200, growth: 1.006 },
  { youtube_channel_id: "UCiJ3kL6mNqR9vU5xPzAbCQg", title: "wanderlens", connected: false,
    description: "travel photography, city guides, and budget backpacking tips",
    subscriber_count: 41_700, video_count: 203, view_count: 9_600_000,
    base_views: 2200, growth: 1.001 },
  { youtube_channel_id: "UCkK4lM7nOsS0wV6yQtBdEQg", title: "maker bench", connected: true,
    description: "woodworking, 3D printing, electronics projects, and shop builds",
    subscriber_count: 28_900, video_count: 132, view_count: 4_300_000,
    base_views: 900, growth: 1.004 }
]

channels = channels_data.map do |attrs|
  meta = attrs.slice(:base_views, :growth)
  ch_attrs = attrs.except(:base_views, :growth)
  ch = Channel.find_or_initialize_by(youtube_channel_id: ch_attrs[:youtube_channel_id])
  ch.assign_attributes(ch_attrs)
  ch.save!
  { channel: ch, base_views: meta[:base_views], growth: meta[:growth] }
end

puts "  #{channels.size} channels"

puts "seeding videos..."

# Title templates per channel niche
title_templates = {
  "daily drive" => [
    -> { "why I #{%w[switched stopped started tried].sample} #{%w[using building shipping testing].sample} #{%w[rails react postgres redis docker kubernetes].sample}" },
    -> { "#{%w[weekly daily].sample} #{%w[update recap vlog].sample} — #{(Date.current - rand(1..90)).strftime('%b %d')}" },
    -> { "honest take: #{%w[remote\ work burnout side\ projects freelancing open\ source].sample} in #{%w[2025 2026].sample}" },
    -> { "I #{%w[built shipped launched broke fixed].sample} #{%w[my\ app a\ SaaS the\ deploy my\ homelab].sample} — here's what happened" },
    -> { "#{rand(3..10)} things I wish I knew about #{%w[startups coding YouTube content\ creation].sample}" }
  ],
  "code kitchen" => [
    -> { "how to #{%w[build deploy test debug refactor optimize].sample} #{%w[rails\ apps APIs background\ jobs webhooks auth\ systems].sample}" },
    -> { "#{%w[ruby rails hotwire turbo stimulus sidekiq].sample} #{%w[crash\ course deep\ dive walkthrough tutorial].sample}" },
    -> { "building a #{%w[blog e-commerce chat\ app dashboard CMS].sample} with #{%w[rails\ 8 hotwire turbo\ streams stimulus].sample}" },
    -> { "#{%w[postgres mysql redis meilisearch elasticsearch].sample} #{%w[tips tricks performance indexing].sample} for #{%w[rails developers beginners].sample}" },
    -> { "the truth about #{%w[microservices monoliths serverless GraphQL REST].sample}" }
  ],
  "competitor watch" => [
    -> { "#{%w[massive huge record-breaking].sample} #{%w[update announcement launch rebrand].sample} — what it means" },
    -> { "why #{%w[everyone creators brands companies].sample} are #{%w[switching leaving moving pivoting].sample} to #{%w[shorts TikTok threads].sample}" },
    -> { "#{%w[algorithm monetization copyright strike].sample} #{%w[changes update drama news].sample} #{(Date.current - rand(1..60)).strftime('%b %Y')}" },
    -> { "I analyzed #{rand(100..1000)} #{%w[channels videos creators thumbnails].sample} — here's what works" }
  ],
  "pixel plates" => [
    -> { "#{%w[perfect ultimate foolproof scientific].sample} #{%w[sourdough ramen steak pasta pizza risotto tacos].sample} #{%w[recipe technique method].sample}" },
    -> { "I #{%w[tried tested perfected].sample} #{%w[Gordon\ Ramsay's Kenji's Babish's].sample} #{%w[recipe technique method].sample}" },
    -> { "sous vide #{%w[chicken beef pork salmon eggs].sample} — #{%w[temperature time science].sample} explained" },
    -> { "#{%w[meal\ prep batch\ cooking fermentation smoking].sample} #{%w[guide for\ beginners masterclass].sample}" },
    -> { "#{rand(3..10)} #{%w[kitchen\ gadgets ingredients tools techniques].sample} that changed my cooking" }
  ],
  "summit sessions" => [
    -> { "#{%w[hiking trail\ running backpacking climbing].sample} #{%w[the\ Alps Patagonia the\ Dolomites Yosemite the\ PCT].sample}" },
    -> { "#{%w[solo winter night sunrise].sample} #{%w[hike camp trek climb].sample} — #{%w[epic brutal peaceful stunning].sample} views" },
    -> { "#{%w[gear\ review tent\ test boot\ review pack\ shakedown].sample}: #{%w[Osprey Arc'teryx Salomon MSR].sample}" },
    -> { "#{rand(3..7)} #{%w[mistakes tips lessons essentials].sample} for #{%w[beginners thru-hikers ultralight\ backpacking].sample}" }
  ],
  "neon arcade" => [
    -> { "#{%w[retro indie hidden\ gem underrated classic].sample} #{%w[game review playthrough analysis].sample}: #{%w[Celeste Hades Stardew\ Valley Hollow\ Knight Balatro].sample}" },
    -> { "I played #{%w[the\ worst the\ best every a\ random].sample} #{%w[NES SNES N64 PS1 GameBoy].sample} game" },
    -> { "game dev #{%w[diary devlog update progress].sample} ##{rand(1..30)} — #{%w[sprites physics UI multiplayer].sample}" },
    -> { "#{%w[ranking comparing reviewing].sample} every #{%w[Zelda Mario Metroid Castlevania Mega\ Man].sample} game" }
  ],
  "sound lab" => [
    -> { "#{%w[mixing mastering recording producing].sample} #{%w[vocals drums bass guitars synths].sample} — #{%w[tips mistakes workflow].sample}" },
    -> { "#{%w[Ableton Logic Pro\ Tools FL\ Studio Reaper].sample} #{%w[tutorial workflow tips hidden\ features].sample}" },
    -> { "#{%w[analog digital budget pro].sample} #{%w[compressor EQ reverb mic preamp].sample} #{%w[shootout review comparison].sample}" },
    -> { "how to get a #{%w[professional radio-ready punchy warm clean].sample} #{%w[mix master sound vocal\ tone].sample}" }
  ],
  "iron protocol" => [
    -> { "#{%w[squat deadlift bench\ press overhead\ press pull-up].sample} #{%w[form guide technique mistakes science].sample}" },
    -> { "#{%w[full-body push/pull/legs upper/lower 5x5 531].sample} #{%w[program routine split].sample} #{%w[explained reviewed tested].sample}" },
    -> { "#{%w[creatine protein sleep caffeine].sample} — what the #{%w[science research studies].sample} actually say" },
    -> { "#{rand(3..10)} #{%w[exercises habits mistakes supplements foods].sample} for #{%w[muscle\ growth fat\ loss recovery strength].sample}" },
    -> { "I tried #{%w[carnivore keto fasting bulking cutting].sample} for #{rand(2..12)} #{%w[weeks months days].sample}" }
  ],
  "wanderlens" => [
    -> { "#{%w[Tokyo Lisbon Istanbul Bangkok Marrakech Seoul Oaxaca].sample} #{%w[city\ guide travel\ vlog food\ tour photo\ walk].sample}" },
    -> { "#{%w[budget luxury solo couple].sample} #{%w[travel backpacking trip itinerary].sample} — #{%w[Japan Portugal Turkey Thailand Morocco].sample}" },
    -> { "#{rand(3..10)} #{%w[tips mistakes hacks lessons].sample} for #{%w[travel\ photography street\ photography budget\ travel solo\ travel].sample}" },
    -> { "#{%w[best hidden secret].sample} #{%w[spots cafes views neighborhoods markets].sample} in #{%w[Paris Berlin Barcelona Prague Vienna].sample}" }
  ],
  "maker bench" => [
    -> { "building a #{%w[desk shelf cabinet workbench speaker guitar].sample} from #{%w[scratch walnut plywood reclaimed\ wood].sample}" },
    -> { "3D printing #{%w[tips failures upgrades mods enclosure].sample} — #{%w[Prusa Bambu Ender Voron].sample}" },
    -> { "#{%w[Arduino Raspberry\ Pi ESP32].sample} #{%w[project tutorial build automation].sample}: #{%w[LED\ matrix weather\ station smart\ home robot].sample}" },
    -> { "#{%w[beginner intermediate advanced].sample} #{%w[woodworking electronics soldering CNC].sample} #{%w[project guide tutorial].sample}" }
  ]
}

privacy_statuses = %w[public_video public_video public_video public_video public_video unlisted private_video]
categories = { "daily drive" => 22, "code kitchen" => 28, "competitor watch" => 24,
               "pixel plates" => 26, "summit sessions" => 19, "neon arcade" => 20,
               "sound lab" => 10, "iron protocol" => 17, "wanderlens" => 19, "maker bench" => 28 }
languages = { "daily drive" => %w[en en en], "code kitchen" => %w[en en en],
              "competitor watch" => %w[en en es], "pixel plates" => %w[en en fr it],
              "summit sessions" => %w[en en de], "neon arcade" => %w[en en ja],
              "sound lab" => %w[en en en], "iron protocol" => %w[en en en pt],
              "wanderlens" => %w[en en es pt fr], "maker bench" => %w[en en en de] }
tags_pool = {
  "daily drive" => %w[vlog tech startup coding remote-work productivity],
  "code kitchen" => %w[ruby rails tutorial programming web-dev hotwire],
  "competitor watch" => %w[youtube analysis trends creator-economy news],
  "pixel plates" => %w[cooking recipe food technique kitchen sous-vide],
  "summit sessions" => %w[hiking outdoor adventure trail 4K nature],
  "neon arcade" => %w[gaming retro indie review gamedev pixel-art],
  "sound lab" => %w[music production mixing audio gear tutorial],
  "iron protocol" => %w[fitness strength training nutrition science gym],
  "wanderlens" => %w[travel photography city-guide budget backpacking],
  "maker bench" => %w[diy woodworking 3d-printing electronics maker]
}

video_count = 0
channels.each do |entry|
  channel = entry[:channel]
  base_views = entry[:base_views]
  growth = entry[:growth]
  templates = title_templates[channel.title]
  count = channel.connected? ? 30 : 20

  count.times do |i|
    vid_id = "#{channel.youtube_channel_id[0..5]}_v#{i.to_s.rjust(3, '0')}"
    published = Time.zone.now - rand(5..365).days - rand(0..23).hours
    title = templates.sample.call

    video = Video.find_or_initialize_by(youtube_video_id: vid_id)
    video.assign_attributes(
      channel: channel,
      title: title,
      description: "#{title}. #{channel.description}. published #{published.strftime('%Y-%m-%d')}.",
      published_at: published,
      duration_seconds: rand(90..5400),
      thumbnail_url: "https://i.ytimg.com/vi/#{vid_id}/hqdefault.jpg",
      tags: tags_pool[channel.title].sample(rand(2..5)),
      privacy_status: privacy_statuses.sample,
      category_id: categories[channel.title],
      default_language: languages[channel.title].sample,
      made_for_kids: false
    )
    video.save!
    video_count += 1

    # Generate 90 days of stats with realistic trends
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
