# frozen_string_literal: true

require "rails_helper"

RSpec.describe "config/recurring.yml smoke check", type: :service do
  let(:config) { YAML.load_file(Rails.root.join("config/recurring.yml")) }
  let(:env_config) { config["production"] }

  it "GameIgdbNightlyRefresh is scheduled at 1am UTC" do
    entry = env_config["game_igdb_nightly_refresh"]
    expect(entry).not_to be_nil
    expect(entry["class"]).to eq("GameIgdbNightlyRefresh")
    expect(entry["schedule"]).to eq("0 1 * * *")
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
    removed = %w[nightly_sync sync_channel_stats nightly_reindex
                 reindex_voyage sync_starred_channels
                 video_stats_snapshot_morning video_stats_snapshot_afternoon]
    removed.each do |key|
      expect(env_config.key?(key)).to be(false), "expected #{key} to be removed from production recurring schedule"
    end
  end
end
