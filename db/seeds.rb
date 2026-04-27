# Seed data for development — run with: bin/rails db:seed
# Idempotent: safe to run multiple times

puts "seeding app settings..."
AppSetting.set("max_panes", "5")
puts "  max_panes = 5"
AppSetting.set("pane_title_length", "14")
puts "  pane_title_length = 14"

puts "seeding channels..."

channels_data = [
  { youtube_channel_id: "UCdQHEqTAcFEt5tEaYdTwrMg", title: "daily drive", connected: true,
    description: "daily vlogs, tech reviews, and random thoughts", subscriber_count: 45_200,
    video_count: 312, view_count: 8_750_000,
    base_views: 2000, growth: 1.005 }, # growing channel
  { youtube_channel_id: "UCxR2Z4N5vLcq3CEBU0kDfhQ", title: "code kitchen", connected: true,
    description: "ruby, rails, and web dev tutorials", subscriber_count: 12_800,
    video_count: 98, view_count: 2_100_000,
    base_views: 400, growth: 1.0 }, # steady channel with occasional spikes
  { youtube_channel_id: "UC3pF7kAhLm9QnTCgbJ4dkWg", title: "competitor watch", connected: false,
    description: "a channel I'm keeping an eye on", subscriber_count: 890_000,
    video_count: 1_245, view_count: 120_000_000,
    base_views: 8000, growth: 0.997 } # declining channel
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

verbs = %w[build deploy test debug refactor optimize scale monitor migrate containerize]
nouns = %w[rails react postgres redis sidekiq docker kubernetes nginx elixir typescript]
topics = %w[developers creators beginners experts teams startups]
privacy_statuses = %w[public_video public_video public_video public_video unlisted private_video]

video_count = 0
channels.each do |entry|
  channel = entry[:channel]
  base_views = entry[:base_views]
  growth = entry[:growth]
  count = channel.connected? ? 30 : 15

  count.times do |i|
    vid_id = "#{channel.youtube_channel_id[0..5]}_v#{i.to_s.rjust(3, '0')}"
    published = Time.zone.now - rand(5..180).days - rand(0..23).hours

    title = [
      "how to #{verbs.sample} #{nouns.sample}",
      "why I #{%w[switched stopped started tried].sample} #{%w[using building shipping testing].sample} #{nouns.sample}",
      "#{%w[weekly daily monthly].sample} #{%w[update recap review roundup].sample} — #{published.strftime('%b %d')}",
      "top #{rand(3..10)} #{%w[tools tricks tips mistakes lessons].sample} for #{topics.sample}",
      "building #{nouns.sample} with #{nouns.sample}",
      "#{nouns.sample} vs #{nouns.sample} — honest take",
      "the truth about #{nouns.sample}",
      "I tried #{nouns.sample} for 30 days"
    ].sample

    video = Video.find_or_initialize_by(youtube_video_id: vid_id)
    video.assign_attributes(
      channel: channel,
      title: title,
      description: "video ##{i + 1} on #{channel.title}. published #{published.strftime('%Y-%m-%d')}.",
      published_at: published,
      duration_seconds: rand(120..3600),
      thumbnail_url: "https://i.ytimg.com/vi/#{vid_id}/hqdefault.jpg",
      tags: %w[ruby rails youtube tutorial code dev web api].sample(rand(2..5)),
      privacy_status: privacy_statuses.sample,
      category_id: [ 22, 28, 24, 10 ].sample,
      default_language: %w[en en en es pt fr].sample,
      made_for_kids: false
    )
    video.save!
    video_count += 1

    # Generate 90 days of stats with realistic trends
    days_since_publish = (Date.current - video.published_at.to_date).to_i
    stat_days = [ days_since_publish, 90 ].min

    # Some videos are "viral" — 10% chance of a spike
    is_viral = rand < 0.1
    spike_day = rand(5..30) if is_viral

    stat_days.times do |d|
      date = Date.current - d.days
      days_old = (date - video.published_at.to_date).to_i.clamp(0, 999)

      # Exponential decay from publish date
      decay = [ 1.0 / (1 + days_old * 0.06), 0.08 ].max
      # Channel growth trend applied per day
      trend = growth**(90 - d)
      # Weekend bump (Sat/Sun get ~20% more views)
      weekend = date.on_weekend? ? 1.2 : 1.0
      # Viral spike
      spike = (is_viral && (days_old - spike_day).abs <= 2) ? rand(3.0..6.0) : 1.0

      views = (base_views * decay * trend * weekend * spike * (0.7 + rand * 0.6)).round.clamp(1, 999_999)
      likes = (views * rand(0.03..0.08)).round
      comments = (views * rand(0.005..0.02)).round
      shares = (views * rand(0.002..0.01)).round
      watch_time = (views * video.duration_seconds / 60.0 * rand(0.25..0.65)).round

      VideoStat.find_or_initialize_by(video: video, date: date).tap do |stat|
        stat.assign_attributes(
          views: views,
          likes: likes,
          comments: comments,
          shares: shares,
          watch_time_minutes: watch_time
        )
        stat.save!
      end
    end
  end
end

puts "  #{video_count} videos with stats"
puts "done!"
