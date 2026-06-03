class StartScreensController < ApplicationController
  # Start screen (/start) — unauthenticated landing.
  allow_anonymous :show

  def show
    render(Pito::StartScreen::Component.new(
      repo_url: ENV.fetch("PITO_REPO_URL", "https://github.com/gmrdad82/pito"),
      license_url: ENV.fetch("PITO_LICENSE_URL", "https://www.gnu.org/licenses/agpl-3.0.html"),
      channels: @channels
    ))
  end
end
