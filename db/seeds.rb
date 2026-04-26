# Seed data for development — run with: bin/rails db:seed
# Idempotent: safe to run multiple times

puts "seeding channels..."

channels_data = [
  { youtube_channel_id: "UCdQHEqTAcFEt5tEaYdTwrMg", title: "daily drive", connected: true,
    description: "daily vlogs, tech reviews, and random thoughts", subscriber_count: 45_200,
    video_count: 312, view_count: 8_750_000 },
  { youtube_channel_id: "UCxR2Z4N5vLcq3CEBU0kDfhQ", title: "code kitchen", connected: true,
    description: "ruby, rails, and web dev tutorials", subscriber_count: 12_800,
    video_count: 98, view_count: 2_100_000 },
  { youtube_channel_id: "UC3pF7kAhLm9QnTCgbJ4dkWg", title: "competitor watch", connected: false,
    description: "a channel I'm keeping an eye on", subscriber_count: 890_000,
    video_count: 1_245, view_count: 120_000_000 }
]

channels = channels_data.map do |attrs|
  Channel.find_or_initialize_by(youtube_channel_id: attrs[:youtube_channel_id]).tap do |ch|
    ch.assign_attributes(attrs)
    ch.save!
  end
end

puts "  #{channels.size} channels"

puts "seeding videos..."

video_categories = { 22 => "people & blogs", 28 => "science & technology", 24 => "entertainment", 10 => "music" }
privacy_statuses = %w[public_video public_video public_video unlisted private_video]

video_count = 0
channels.each do |channel|
  count = channel.connected? ? 30 : 15

  count.times do |i|
    vid_id = "#{channel.youtube_channel_id[0..5]}_v#{i.to_s.rjust(3, '0')}"
    published = Time.zone.now - rand(1..365).days - rand(0..23).hours

    video = Video.find_or_initialize_by(youtube_video_id: vid_id)
    video.assign_attributes(
      channel: channel,
      title: [
        "how to #{%w[build deploy test debug refactor optimize scale monitor].sample} #{%w[rails react postgres redis sidekiq docker kubernetes nginx].sample}",
        "#{%w[weekly daily monthly].sample} #{%w[update recap review roundup].sample} — #{published.strftime('%b %d')}",
        "#{%w[why what how when].sample} #{%w[I we you they].sample} #{%w[switched stopped started tried].sample} #{%w[using building shipping testing].sample} #{%w[this that it everything].sample}",
        "#{%w[top best worst].sample} #{rand(3..10)} #{%w[tools tricks tips mistakes lessons].sample} for #{%w[developers creators beginners experts].sample}"
      ].sample,
      description: "video ##{i + 1} on #{channel.title}. published #{published.strftime('%Y-%m-%d')}.",
      published_at: published,
      duration_seconds: rand(120..3600),
      thumbnail_url: "https://i.ytimg.com/vi/#{vid_id}/hqdefault.jpg",
      tags: %w[ruby rails youtube tutorial code dev web api].sample(rand(2..5)),
      privacy_status: privacy_statuses.sample,
      category_id: video_categories.keys.sample,
      default_language: %w[en en en es pt fr].sample,
      made_for_kids: false
    )
    video.save!
    video_count += 1

    # add some stats
    rand(7..30).times do |d|
      date = Date.current - d.days
      VideoStat.find_or_initialize_by(video: video, date: date).tap do |stat|
        stat.assign_attributes(
          views: rand(10..5000),
          likes: rand(1..500),
          comments: rand(0..50),
          shares: rand(0..30),
          watch_time_minutes: rand(5..2000)
        )
        stat.save!
      end
    end
  end
end

puts "  #{video_count} videos with stats"
puts "done!"
