class CommandsController < ApplicationController
  # POST /commands/execute
  # Body: { "command": "reindex meilisearch" }
  # Returns: { "output": "...", "error": null } or { "output": null, "error": "..." }
  def execute
    cmd = params[:command].to_s.strip
    return render json: { error: "empty command" }, status: :unprocessable_entity if cmd.blank?

    parts = cmd.split(/\s+/)
    action = parts[0]
    args = parts[1..]

    result = case action
    when "help"
      help_output
    when "status"
      status_output
    when "channels"
      channels_output
    when "videos"
      videos_output
    when "reindex"
      reindex_output(args)
    when "games"
      games_output
    when "config"
      config_output(args)
    else
      { error: "unknown command: #{action}" }
    end

    if result[:error]
      render json: result, status: :unprocessable_entity
    else
      render json: result
    end
  end

  private

  def help_output
    { output: "commands:\n  /status /channels /videos /auth /reindex /games /config" }
  end

  def status_output
    { output: "channels  #{Channel.count}\nvideos    #{Video.count}\nfootage   #{Footage.count}" }
  end

  def channels_output
    lines = Channel.order(:channel_url).map do |ch|
      star = ch.star ? "★" : " "
      "#{star} #{ch.channel_url}"
    end
    { output: lines.join("\n") }
  end

  def videos_output
    lines = Video.order(created_at: :desc).limit(30).map do |v|
      "#{v.youtube_video_id}  #{v.view_count} views"
    end
    { output: lines.join("\n") }
  end

  def reindex_output(args)
    target = args[0]
    unless %w[voyage].include?(target)
      return { error: "usage: reindex voyage" }
    end
    VoyageReindexJob.perform_later
    { output: "voyage reindex queued" }
  end

  def games_output
    games = Game.where.not(release_date: nil)
                .where("release_date > ?", Time.current)
                .order(release_date: :asc)
                .limit(20)
    if games.any?
      lines = games.map { |g| "#{g.title}  #{g.release_date.strftime('%Y-%m-%d')}" }
      { output: lines.join("\n") }
    else
      { output: "no upcoming games" }
    end
  end

  def config_output(args)
    sub = args[0]
    case sub
    when nil, "show"
      setting = AppSetting.singleton_row
      { output: "notifications_all: #{setting.notifications_send_all}\nnotifications_daily_digest: #{setting.notifications_send_daily_digest}\ntheme: dark" }
    else
      { error: "config subcommands: show (default)" }
    end
  end
end
