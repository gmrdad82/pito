class SearchController < ApplicationController
  def show
    @query = params[:q].to_s.strip
    @page = [ params[:page].to_i, 1 ].max

    if @query.blank?
      @videos = { hits: [], total: 0, took_ms: 0 }
      return
    end

    engine = Pito::Search.engine
    @videos = engine.search(Video, @query, page: @page, per_page: 20)

    respond_to do |format|
      format.html
      format.json do
        render json: search_json_payload
      end
    end
  end

  private

  # Flat shape for external API consumers:
  #   { query, videos: [SearchHit<Video>], video_total, took_ms }
  # where each SearchHit is { record: <Video summary>, highlights }.
  # Hits whose backing Video row no longer exists are dropped so the
  # `record` field is never null, which would break strict client
  # deserialization.
  def search_json_payload
    hits = (@videos[:hits] || []).filter_map { |hit| search_hit_json(hit) }
    {
      query: @query,
      videos: hits,
      video_total: @videos[:total].to_i,
      took_ms: @videos[:took_ms].to_f
    }
  end

  def search_hit_json(hit)
    record = hit[:record]
    return nil unless record
    {
      record: VideoDecorator.new(record).as_summary_json,
      highlights: stringify_highlights(hit[:highlights])
    }
  end

  # The search payload echoes document fields — arrays are joined with commas;
  # everything else is converted via `to_s`.
  def stringify_highlights(raw)
    return {} unless raw.is_a?(Hash)
    raw.each_with_object({}) do |(k, v), out|
      out[k.to_s] = case v
      when String then v
      when Array  then v.join(", ")
      else v.to_s
      end
    end
  end
end
