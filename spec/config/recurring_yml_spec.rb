# frozen_string_literal: true

require "rails_helper"

RSpec.describe "config/recurring.yml smoke check", type: :service do
  let(:config) { YAML.load_file(Rails.root.join("config/recurring.yml")) }
  let(:env_config) { config["production"] }

  it "NightlySyncJob (daily new-video sync) is scheduled at 1am UTC" do
    entry = env_config["nightly_sync"]
    expect(entry).not_to be_nil
    expect(entry["class"]).to eq("NightlySyncJob")
    expect(entry["schedule"]).to eq("0 1 * * *")
  end

  it "VideoStatsSnapshotJob runs twice intraday (09:00 + 17:00 UTC)" do
    morning   = env_config["video_stats_snapshot_morning"]
    afternoon = env_config["video_stats_snapshot_afternoon"]
    expect(morning).not_to be_nil
    expect(afternoon).not_to be_nil
    expect(morning["class"]).to eq("VideoStatsSnapshotJob")
    expect(afternoon["class"]).to eq("VideoStatsSnapshotJob")
    expect(morning["schedule"]).to eq("0 9 * * *")
    expect(afternoon["schedule"]).to eq("0 17 * * *")
  end

  it "CleanupNotificationsJob is scheduled" do
    entry = env_config["cleanup_notifications"]
    expect(entry).not_to be_nil
    expect(entry["class"]).to eq("CleanupNotificationsJob")
  end

  it "SolidQueue housekeeping entry is present" do
    entry = env_config["clear_solid_queue_finished_jobs"]
    expect(entry).not_to be_nil
    expect(entry["schedule"]).to eq("every hour at minute 12")
  end

  it "CloudflareTrustedProxiesRefresherJob is scheduled" do
    entry = env_config["cloudflare_trusted_proxies_refresher"]
    expect(entry).not_to be_nil
    expect(entry["class"]).to eq("CloudflareTrustedProxiesRefresherJob")
  end

  it "removed data-sync entries are absent" do
    # game_igdb_nightly_refresh is now folded into NightlySyncJob's fan-out.
    removed = %w[game_igdb_nightly_refresh sync_channel_stats nightly_reindex
                 reindex_voyage sync_starred_channels]
    removed.each do |key|
      expect(env_config.key?(key)).to be(false), "expected #{key} to be removed from production recurring schedule"
    end
  end
end
