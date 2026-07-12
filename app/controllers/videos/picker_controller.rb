# frozen_string_literal: true

module Videos
  # The videos picker's pager + the TUI's JSON picker feed.
  #
  # Turbo Stream (`?after=<opaque cursor>`): APPEND the next page's rows into
  # the picker's rows container and REPLACE the pager sentinel — the same
  # shape the notifications panel answers (the generic pito--list-pager
  # drives it). JSON: `{rows: [{id, title, handle}], next_cursor}` pages the
  # same keyset for pito-tui's `show vid` picker. Optional `q=` filters by title
  # (same ILIKE as search-local) on both formats; cursors page within the
  # filtered set, so callers repeat q= alongside after=.
  #
  # Auth: session-gated by the concern (anonymous JSON → 401, matching the
  # house convention).
  class PickerController < ApplicationController
    def index
      videos, next_cursor = Video.picker_page(after: params[:after], q: params[:q])

      respond_to do |format|
        format.turbo_stream do
          render "videos/picker_page", locals: { videos:, next_cursor: }
        end
        format.json do
          render json: {
            rows: videos.map { |v|
              { id: v.id, title: v.title, handle: v.channel&.handle }
            },
            next_cursor: next_cursor
          }
        end
        format.html { redirect_to root_path }
      end
    end
  end
end
