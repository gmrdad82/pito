class TerminalController < ApplicationController
  # Chat shell (/) — the main pito interface.
  allow_anonymous :show

  def show
    @events = Pito::Sample::ChatShell.events
  end
end
