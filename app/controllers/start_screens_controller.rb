class StartScreensController < ApplicationController
  # Start screen (/start) — unauthenticated landing.
  allow_anonymous :show, :not_found

  def show
    # SHOWCASE-START-NOTFOUND: seed suggestions for authenticated users only.
    # Unauthenticated visitors get [] so no comet cycles and the login-hint
    # native placeholder remains visible.
    initial_showcase = Current.session.present? ? Pito::Showcase::Builder.call(conversation: nil) : []
    render(Pito::StartScreen::Component.new(
      repo_url: ENV.fetch("PITO_REPO_URL", "https://github.com/gmrdad82/pito"),
      license_url: ENV.fetch("PITO_LICENSE_URL", "https://www.gnu.org/licenses/agpl-3.0.html"),
      channels: @channels,
      suggestions: initial_showcase
    ))
  end

  # Dynamic 404 — renders the start screen with the suggestions-enabled
  # chatbox so unknown URLs never land on the static public/404.html fallback.
  # Delegates to ApplicationController#render_not_found which already handles
  # auth-awareness via the session cookie.
  def not_found
    render_not_found
  end
end
