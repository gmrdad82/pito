require "rails_helper"

RSpec.describe "analytics schema integrity", type: :model do
  let(:connection) { ActiveRecord::Base.connection }

  ANALYTICS_TABLES = %w[
    channel_dailies
    video_dailies
    video_daily_by_countries
    video_daily_by_device_types
    video_daily_by_operating_systems
    video_daily_by_traffic_sources
    video_daily_by_subscribed_statuses
    video_daily_by_age_group_genders
    channel_window_summaries
    video_window_summaries
    top_videos_windows
    video_retentions
  ].freeze

  it "defines analytics_window as a Postgres enum with the four documented values" do
    labels = connection.select_values(<<~SQL)
      SELECT enumlabel FROM pg_enum
      WHERE enumtypid = (SELECT oid FROM pg_type WHERE typname = 'analytics_window')
      ORDER BY enumsortorder
    SQL
    expect(labels).to eq(%w[7d 28d 90d lifetime])
  end

  it "places UNIQUE indexes on every natural key" do
    expected = {
      "channel_dailies"                     => %w[channel_id date],
      "video_dailies"                       => %w[video_id date],
      "video_daily_by_countries"            => %w[video_id date country_code],
      "video_daily_by_device_types"         => %w[video_id date device_type],
      "video_daily_by_operating_systems"    => %w[video_id date operating_system],
      "video_daily_by_traffic_sources"      => %w[video_id date traffic_source_type],
      "video_daily_by_subscribed_statuses"  => %w[video_id date subscribed_status],
      "video_daily_by_age_group_genders"    => %w[video_id date age_group gender],
      "channel_window_summaries"            => %w[channel_id window],
      "video_window_summaries"              => %w[video_id window],
      "video_retentions"                    => %w[video_id elapsed_ratio_bucket]
    }
    expected.each do |table, columns|
      uniq = connection.indexes(table).select(&:unique).map(&:columns)
      expect(uniq).to include(columns), "expected UNIQUE on #{table}(#{columns.join(', ')})"
    end

    # top_videos_windows has TWO unique composite indexes.
    top_uniq = connection.indexes("top_videos_windows").select(&:unique).map(&:columns)
    expect(top_uniq).to include(%w[channel_id window video_id])
    expect(top_uniq).to include(%w[channel_id window rank])
  end

  it "places ON DELETE CASCADE on every FK to channels and videos" do
    rows = connection.select_all(<<~SQL).to_a
      SELECT tc.table_name, kcu.column_name, rc.delete_rule, ccu.table_name AS ref_table
      FROM information_schema.referential_constraints rc
        JOIN information_schema.table_constraints tc
          ON tc.constraint_name = rc.constraint_name
        JOIN information_schema.key_column_usage kcu
          ON kcu.constraint_name = rc.constraint_name
        JOIN information_schema.constraint_column_usage ccu
          ON ccu.constraint_name = rc.constraint_name
      WHERE tc.table_name = ANY(ARRAY[#{ANALYTICS_TABLES.map { |t| "'#{t}'" }.join(', ')}])
        AND ccu.table_name IN ('channels', 'videos')
    SQL

    expect(rows).not_to be_empty
    rows.each do |row|
      expect(row["delete_rule"]).to eq("CASCADE"),
        "expected ON DELETE CASCADE on #{row['table_name']}.#{row['column_name']} → #{row['ref_table']}"
    end
  end

  it "leaves no analytics table with a tenant_id column" do
    rows = connection.select_values(<<~SQL)
      SELECT table_name FROM information_schema.columns
      WHERE column_name = 'tenant_id'
        AND table_name = ANY(ARRAY[#{ANALYTICS_TABLES.map { |t| "'#{t}'" }.join(', ')}])
    SQL
    expect(rows).to be_empty
  end

  it "leaves no analytics table with the wrong numeric scale on ratio columns" do
    ratio_columns = {
      "channel_window_summaries" => %w[
        average_view_percentage
        video_thumbnail_impressions_click_rate
        card_click_rate
        card_teaser_click_rate
      ],
      "video_window_summaries" => %w[
        average_view_percentage
        video_thumbnail_impressions_click_rate
        card_click_rate
        card_teaser_click_rate
      ],
      "video_daily_by_countries"           => %w[average_view_percentage],
      "video_daily_by_device_types"        => %w[average_view_percentage],
      "video_daily_by_operating_systems"   => %w[average_view_percentage],
      "video_daily_by_traffic_sources"     => %w[video_thumbnail_impressions_click_rate],
      "video_daily_by_subscribed_statuses" => %w[average_view_percentage],
      "video_daily_by_age_group_genders"   => %w[viewer_percentage],
      "video_retentions"                   => %w[audience_watch_ratio relative_retention_performance]
    }
    ratio_columns.each do |table, cols|
      cols.each do |col|
        info = connection.columns(table).find { |c| c.name == col }
        expect(info).not_to be_nil, "missing #{table}.#{col}"
        expect([ info.precision, info.scale ]).to eq([ 10, 6 ]),
          "expected #{table}.#{col} numeric(10, 6)"
      end
    end
  end

  it "leaves no analytics table with the wrong numeric scale on duration columns" do
    duration_columns = {
      "channel_dailies"                  => %w[average_view_duration],
      "video_dailies"                    => %w[average_view_duration],
      "video_daily_by_countries"         => %w[average_view_duration],
      "video_daily_by_device_types"      => %w[average_view_duration],
      "video_daily_by_operating_systems" => %w[average_view_duration],
      "channel_window_summaries"         => %w[average_view_duration],
      "video_window_summaries"           => %w[average_view_duration],
      "top_videos_windows"               => %w[average_view_duration]
    }
    duration_columns.each do |table, cols|
      cols.each do |col|
        info = connection.columns(table).find { |c| c.name == col }
        expect(info).not_to be_nil, "missing #{table}.#{col}"
        expect([ info.precision, info.scale ]).to eq([ 10, 2 ]),
          "expected #{table}.#{col} numeric(10, 2)"
      end
    end
  end
end
