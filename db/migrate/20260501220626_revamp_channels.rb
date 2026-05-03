class RevampChannels < ActiveRecord::Migration[8.1]
  BASE62 = ((("A".."Z").to_a + ("a".."z").to_a + ("0".."9").to_a + %w[_ -]).freeze)

  def up
    # Phase A is seed-only data; we still produce a minimal-but-valid backfill so
    # the constraints can apply cleanly. db:seed re-creates a clean dataset after
    # this migration.
    seeded_tenant_id = ensure_default_tenant_id

    # Drop the old unique index before dropping the underlying column.
    if index_exists?(:channels, :youtube_channel_id, name: "index_channels_on_youtube_channel_id")
      remove_index :channels, name: "index_channels_on_youtube_channel_id"
    end

    # Add new columns as nullable / with defaults so the backfill can fill them
    # before we tighten constraints.
    change_table :channels, bulk: true do |t|
      t.references :tenant, foreign_key: true, index: true
      t.string :channel_url
      t.boolean :star, null: false, default: false
      t.boolean :syncing, null: false, default: false
    end

    backfill_existing_rows(seeded_tenant_id)

    # Tighten constraints once data is filled in.
    change_column_null :channels, :tenant_id, false
    change_column_null :channels, :channel_url, false

    # Drop Alpha columns now that nothing depends on them in this migration.
    change_table :channels, bulk: true do |t|
      t.remove :description, type: :text
      t.remove :oauth_access_token, type: :text
      t.remove :oauth_expires_at, type: :datetime
      t.remove :oauth_refresh_token, type: :text
      t.remove :oauth_scopes, type: :string
      t.remove :subscriber_count, type: :integer
      t.remove :thumbnail_url, type: :string
      t.remove :title, type: :string
      t.remove :video_count, type: :integer
      t.remove :view_count, type: :bigint
      t.remove :youtube_channel_id, type: :string
    end

    add_index :channels, :channel_url, unique: true
    add_index :channels, [ :tenant_id, :star ]
    add_index :channels, [ :tenant_id, :connected ]
    add_index :channels, [ :tenant_id, :syncing ]
    add_index :channels, :last_synced_at
  end

  def down
    remove_index :channels, :last_synced_at if index_exists?(:channels, :last_synced_at)
    remove_index :channels, [ :tenant_id, :syncing ] if index_exists?(:channels, [ :tenant_id, :syncing ])
    remove_index :channels, [ :tenant_id, :connected ] if index_exists?(:channels, [ :tenant_id, :connected ])
    remove_index :channels, [ :tenant_id, :star ] if index_exists?(:channels, [ :tenant_id, :star ])
    remove_index :channels, :channel_url if index_exists?(:channels, :channel_url)

    change_table :channels, bulk: true do |t|
      t.string :youtube_channel_id
      t.string :title
      t.text :description
      t.string :thumbnail_url
      t.integer :subscriber_count
      t.integer :video_count
      t.bigint :view_count
      t.text :oauth_access_token
      t.text :oauth_refresh_token
      t.datetime :oauth_expires_at
      t.string :oauth_scopes
    end

    add_index :channels, :youtube_channel_id, unique: true

    change_table :channels, bulk: true do |t|
      t.remove :syncing, type: :boolean
      t.remove :star, type: :boolean
      t.remove :channel_url, type: :string
      t.remove_references :tenant, foreign_key: true, index: true
    end
  end

  private

  def ensure_default_tenant_id
    existing = select_value("SELECT id FROM tenants ORDER BY id ASC LIMIT 1")
    return existing if existing

    now = connection.quote(Time.current)
    execute(<<~SQL)
      INSERT INTO tenants (name, created_at, updated_at)
      VALUES ('Primary', #{now}, #{now})
    SQL

    select_value("SELECT id FROM tenants ORDER BY id ASC LIMIT 1")
  end

  def backfill_existing_rows(seeded_tenant_id)
    rng = Random.new(42)
    rows = select_all("SELECT id, youtube_channel_id FROM channels ORDER BY id ASC")

    rows.each do |row|
      url = derive_channel_url(row["id"], row["youtube_channel_id"], rng)
      execute(<<~SQL)
        UPDATE channels
        SET tenant_id = #{seeded_tenant_id.to_i},
            channel_url = #{connection.quote(url)}
        WHERE id = #{row["id"].to_i}
      SQL
    end
  end

  def derive_channel_url(id, existing_yt_id, rng)
    if existing_yt_id.is_a?(String) && existing_yt_id =~ /\AUC[A-Za-z0-9_-]{22}\z/
      "https://www.youtube.com/channel/#{existing_yt_id}"
    else
      suffix = id.to_s
      pad = (22 - suffix.length).clamp(0, 22)
      filler = Array.new(pad) { BASE62[rng.rand(BASE62.length)] }.join
      handle = (suffix + filler)[0, 22]
      "https://www.youtube.com/channel/UC#{handle}"
    end
  end

  def select_value(sql)
    connection.select_value(sql)
  end

  def select_all(sql)
    connection.select_all(sql)
  end
end
