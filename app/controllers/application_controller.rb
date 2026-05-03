class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  # Translate ActiveRecord::RecordNotFound into a clean JSON 404 for JSON
  # requests so pito-sh (and any other JSON consumer) gets a parseable error
  # body instead of an HTML error page. HTML still returns a plain 404 page.
  rescue_from ActiveRecord::RecordNotFound, with: :render_not_found

  private

  def render_not_found
    respond_to do |format|
      format.html { render plain: "Not found", status: :not_found }
      format.json { render json: { error: "Not found" }, status: :not_found }
      format.any  { render plain: "Not found", status: :not_found }
    end
  end
end
