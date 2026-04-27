class SavedViewsController < ApplicationController
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

    redirect_path = kind == "channels" ? channels_path : videos_path
    redirect_to redirect_path, notice: "view deleted."
  end

  private

  def saved_view_params
    params.require(:saved_view).permit(:kind, :url, :name)
  end
end
