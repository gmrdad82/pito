class TerminalController < ApplicationController
  # Chat shell (/) — the main pito interface.
  allow_anonymous :show

  def show
    @events = current_conversation.events.includes(:turn).order(:position)
  end
end
