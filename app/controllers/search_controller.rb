class SearchController < ApplicationController
  def show
    @query = params[:q].to_s.strip
    @page = [ params[:page].to_i, 1 ].max

    if @query.blank?
      @channels = { hits: [], total: 0, took_ms: 0 }
      @videos = { hits: [], total: 0, took_ms: 0 }
      return
    end

    engine = Search.engine
    @channels = engine.search(Channel, @query, page: @page, per_page: 20)
    @videos = engine.search(Video, @query, page: @page, per_page: 20)

    respond_to do |format|
      format.html
      format.json do
        render json: {
          query: @query,
          channels: { hits: @channels[:hits].map { |h| h.except(:record) }, total: @channels[:total], took_ms: @channels[:took_ms] },
          videos: { hits: @videos[:hits].map { |h| h.except(:record) }, total: @videos[:total], took_ms: @videos[:took_ms] }
        }
      end
    end
  end
end
