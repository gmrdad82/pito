# frozen_string_literal: true

# Owner ruling, 2026-07-15: the Voyage account is retired with 3.0.0, and the
# stored API key is retired with it. This is the release chain's one
# deliberate destructive statement — scoped to this single retired
# credential. It does NOT touch the 1024-dim embedding columns; those still
# ride the owner-gated finalize step. Rolling back restores the (empty)
# column, not the key — that's accepted, it's the point.
class RemoveVoyageApiKeyFromAppSettings < ActiveRecord::Migration[8.1]
  def change
    remove_column :app_settings, :voyage_api_key, :text
  end
end
