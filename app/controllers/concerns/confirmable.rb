# Shared logic for action-confirmation controllers (Deletions, Syncs, etc).
#
# Provides:
#   - load_items   : parses :type / :ids params, populates @type and @items
#                    (with type-appropriate eager loading), redirects on
#                    unknown type or empty result.
#   - cancel_path  : index path for the type (channels_path / videos_path /
#                    projects_path / collections_path / games_path / root_path).
#   - model_for    : type → ActiveRecord class dispatch helper.
#   - label_for    : human-friendly label per item, used by both HTML preview
#                    rows and the JSON preview shape.
#
# Including controllers can call `before_action :load_items` to plug in.
module Confirmable
  extend ActiveSupport::Concern

  # Phase B post-validation: extended to cover Project Workspace types so
  # `[delete]` links from project / collection / game show pages route
  # cleanly through the deletions framework. Footage stays out — its
  # delete flow (if any) is owned by the importer surface, not the web UI.
  TYPES = %w[channel video project collection game note timeline calendar_entry bundle video_game_link].freeze

  private

  def load_items
    @type = params[:type].to_s
    ids = params[:ids].to_s.split(",").reject(&:blank?)

    unless TYPES.include?(@type)
      respond_to do |format|
        format.html { redirect_to root_path, alert: "unknown type." }
        format.json { render json: { error: "unknown type" }, status: :unprocessable_content }
      end
      return
    end

    @items = scope_for(@type, ids)

    if ids.empty?
      respond_to do |format|
        format.html { redirect_to cancel_path, alert: "nothing to #{action_verb}." }
        # Phase 21 — JSON parity. CLI / MCP callers parse this string,
        # so the envelope is normative ("no_ids_supplied" rather than
        # the free-form HTML alert text).
        format.json { render json: { error: "no_ids_supplied" }, status: :unprocessable_content }
      end
      return
    end

    if @items.blank? || (@items.respond_to?(:empty?) && @items.empty?)
      respond_to do |format|
        format.html { redirect_to cancel_path, alert: "nothing to #{action_verb}." }
        format.json { render json: { error: "nothing to #{action_verb}" }, status: :unprocessable_content }
      end
      return
    end

    @cancel_path = cancel_path
  end

  def cancel_path
    case @type
    when "channel"    then channels_path
    when "video"      then videos_path
    when "project"    then projects_path
    when "collection" then collections_path
    when "game"       then games_path
    # Notes and timelines have no top-level user-facing index — they are
    # rendered inside the project show page. Cancel returns to the
    # projects index, which is the closest reasonable parent.
    when "note"       then projects_path
    when "timeline"   then projects_path
    # Phase 15 §2 — calendar entries cancel back to the schedule view
    # (the closest surface that always renders).
    when "calendar_entry" then calendar_schedule_path
    when "bundle"     then bundles_path
    # Phase 14 §3 — video_game_link cancel returns to the parent video
    # edit page. The deletion screen is reached from the [remove]
    # button on the video edit form.
    when "video_game_link" then videos_path
    else root_path
    end
  end

  def model_for(type)
    case type
    when "channel"    then Channel
    when "video"      then Video
    when "project"    then Project
    when "collection" then Collection
    when "game"       then Game
    when "note"       then Note
    when "timeline"   then Timeline
    when "calendar_entry" then CalendarEntry
    when "bundle"     then Bundle
    when "video_game_link" then VideoGameLink
    end
  end

  # Per-type collection with the eager-loading shape that both deletions and
  # syncs need to render the preview rows. Channels are ordered by URL (the
  # only stable display attribute now that `title` is gone). Videos retain
  # the aggregated stats projection so the deletion preview can show totals.
  # Phase 4 types order by their human-facing display column.
  def scope_for(type, ids)
    case type
    when "channel"
      Channel.where(id: ids).order(channel_url: :asc)
    when "video"
      # Phase 7 Path A2 — Video has no `title` to order by. Order by
      # youtube_video_id (stable, monotonic enough for preview rows).
      Video.includes(:channel)
           .left_joins(:video_stats)
           .select(
             "videos.*",
             "COALESCE(SUM(video_stats.views), 0) AS total_views",
             "COALESCE(SUM(video_stats.likes), 0) AS total_likes",
             "COALESCE(SUM(video_stats.comments), 0) AS total_comments",
             "COALESCE(CAST(SUM(video_stats.watch_time_minutes) AS BIGINT), 0) AS total_watch_time"
           )
           .where(id: ids)
           .group("videos.id")
           .order(youtube_video_id: :asc)
    when "project"
      Project.where(id: ids).order(name: :asc)
    when "collection"
      Collection.where(id: ids).order(name: :asc)
    when "game"
      Game.where(id: ids).order(title: :asc)
    when "note"
      Note.includes(:project).where(id: ids).order(title: :asc)
    when "timeline"
      Timeline.includes(:project).where(id: ids).order(title: :asc)
    when "calendar_entry"
      # Phase 15 §2 — exclude derived/auto entries from manual cancel.
      # The schedule / month views do not render the [cancel] link on
      # those rows; this guard is defense-in-depth for direct URL hits.
      CalendarEntry.where(id: ids).where(source: :manual).order(starts_at: :asc)
    when "bundle"
      Bundle.where(id: ids).order(name: :asc)
    when "video_game_link"
      VideoGameLink.includes(:game, :bundle, :video).where(id: ids).order(:id)
    end
  end

  # Display label used by JSON preview responses (and mirrored by the HTML
  # views): channel_url for channels, title for videos, name for
  # projects/collections, title for games/notes/timelines.
  def label_for(item)
    case item
    when Channel    then item.channel_url
    when Video      then item.youtube_video_id
    when Project    then item.name
    when Collection then item.name
    when Game       then item.title
    when Note       then item.title
    when Timeline   then item.title
    when CalendarEntry then item.title
    when Bundle        then item.name
    when VideoGameLink
      target = item.target
      target_label = target.respond_to?(:title) ? target.title : target&.name
      "video ##{item.video_id} → #{item.link_type}: #{target_label}"
    else item.to_s
    end
  end

  # Override in including controller to customize the redirect alert text
  # ("nothing to delete." vs "nothing to sync.").
  def action_verb
    "act on"
  end
end
