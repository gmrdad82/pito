class StartScreensController < ApplicationController
  # Start screen (/start) — unauthenticated landing.
  allow_anonymous :show

  def show
    render(Pito::StartScreen::Component.new(
      version: "0.1.0",
      marketing_url: ENV["PITO_MARKETING_URL"].presence
    ))
  end
end
