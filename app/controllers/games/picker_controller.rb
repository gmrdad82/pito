# frozen_string_literal: true

module Games
  # The games picker's pager + the TUI's JSON picker feed.
  #
  # Turbo Stream (`?after=<opaque cursor>`): APPEND the next page's rows into
  # the picker's rows container and REPLACE the pager sentinel — the same
  # shape the notifications panel answers (the generic pito--list-pager
  # drives it). JSON: `{rows: [{id, title, handle}], next_cursor}` pages the
  # same keyset for pito-tui's `show game` picker. Optional `q=` filters by title
  # (same ILIKE as search-local) on both formats; cursors page within the
  # filtered set, so callers repeat q= alongside after=.
  #
  # Auth: session-gated by the concern (anonymous JSON → 401, matching the
  # house convention).
  class PickerController < ApplicationController
    def index
      games, next_cursor = Game.picker_page(after: params[:after], q: params[:q])

      respond_to do |format|
        format.turbo_stream do
          render "games/picker_page", locals: { games:, next_cursor: }
        end
        format.json do
          render json: {
            rows: games.map { |g| { id: g.id, title: g.title } },
            next_cursor: next_cursor
          }
        end
        format.html { redirect_to root_path }
      end
    end
  end
end
