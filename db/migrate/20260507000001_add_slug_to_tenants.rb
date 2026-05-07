class AddSlugToTenants < ActiveRecord::Migration[8.1]
  # Phase 5A — formalize `tenants.slug`. Citext (case-insensitive),
  # unique, NOT NULL. Backfills any existing tenant rows from the
  # credentials :owner.tenant_slug entry (fallback "primary" if absent).
  # Single-tenant world today, so the backfill targets the seeded
  # singleton tenant; if a future migration ever lands with multiple
  # tenants, this one would need re-thinking — flagged here for the next
  # operator.

  def up
    add_column :tenants, :slug, :citext

    fallback_slug = Rails.application.credentials.dig(:owner, :tenant_slug).presence || "primary"

    # Backfill: every existing tenant gets the fallback slug. There is at
    # most one tenant in the dataset right now (seeded singleton), so
    # collisions are not possible. If a future operator adds tenants
    # before this migration runs, they will collide on the unique index
    # below and this migration will fail loudly — the right outcome.
    rows = execute("SELECT id FROM tenants ORDER BY id ASC")
    rows.each_with_index do |row, idx|
      slug = idx.zero? ? fallback_slug : "#{fallback_slug}-#{idx}"
      execute(ActiveRecord::Base.sanitize_sql([
        "UPDATE tenants SET slug = ? WHERE id = ?", slug, row["id"]
      ]))
    end

    change_column_null :tenants, :slug, false
    add_index :tenants, :slug, unique: true
  end

  def down
    remove_index :tenants, :slug
    remove_column :tenants, :slug
  end
end
