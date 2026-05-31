class SavedViewsController < ApplicationController
  # JSON endpoints are unauthenticated for the single-user dev environment
  # behind the Cloudflare tunnel. Phase 3 Auth Foundation will add API token
  # auth. CSRF is skipped only for JSON requests so the HTML form path keeps
  # its authenticity-token check.
  skip_before_action :verify_authenticity_token, if: -> { request.format.json? }

  # GET /saved_views.json
  #
  # JSON-only listing consumed by the pito CLI terminal client at startup.
  # No HTML view exists; HTML requests fall back to the index page of the
  # entity (channels) since the saved-views surface is rendered inline on
  # the channels and videos pages.
  def index
    @saved_views = SavedView.ordered

    respond_to do |format|
      format.html { redirect_to channels_path }
      format.json do
        render json: @saved_views.map { |v| saved_view_json(v) }
      end
    end
  end

  def create
    @saved_view = SavedView.new(saved_view_params)
    @saved_view.url = CGI.unescape(@saved_view.url) if @saved_view.url.present?
    @saved_view.position = (SavedView.where(kind: @saved_view.kind).maximum(:position) || -1) + 1

    if @saved_view.save
      redirect_to @saved_view.url, notice: "view saved."
    else
      existing = SavedView.find_by(kind: @saved_view.kind, url: @saved_view.url)
      if existing
        redirect_to existing.url, notice: "view already saved."
      else
        redirect_back fallback_location: root_path, alert: "could not save view."
      end
    end
  end

  def destroy
    @saved_view = SavedView.find(params[:id])
    kind = @saved_view.kind
    @saved_view.destroy!

    redirect_to root_path, notice: "view deleted."
  end

  private

  def saved_view_params
    params.require(:saved_view).permit(:kind, :url, :name)
  end

  # Minimal JSON shape for external API consumers: id, kind, name, url.
  # SavedView#ordered scope (position asc, created_at desc) is preserved
  # for stable client rendering.
  def saved_view_json(view)
    {
      id: view.id,
      kind: view.kind,
      name: view.name,
      url: view.url
    }
  end
end
