require "rails_helper"
require "rake"

# Coverage push (2026-05-17). Operator-facing rake wrapper around
# `Backfill::AnalyticsRange.call` for filling missed analytics
# windows from the shell. The wrapper itself is thin — three positional
# args, four `abort` guards, one delegated call — so the specs focus on
# the guard messages, the argument parsing, the side effect (Sidekiq
# enqueues), and the stdout summary line.
RSpec.describe "analytics rake tasks" do
  before(:all) do
    Rake.application.rake_require(
      "tasks/analytics",
      [ Rails.root.join("lib").to_s ],
      []
    )
    Rake::Task.define_task(:environment)
  end

  let(:task) { Rake::Task["analytics:backfill"] }

  before { task.reenable }

  describe "analytics:backfill" do
    let(:user)       { create(:user) }
    let(:connection) { create(:youtube_connection, user: user) }
    let!(:channel)   { create(:channel, youtube_connection: connection) }
    let!(:video)     { create(:video, channel: channel, published_at: 10.days.ago) }
    let(:from)       { 30.days.ago.to_date.to_s }
    let(:to)         { 1.day.ago.to_date.to_s }

    it "enqueues a ChannelAnalyticsSync + VideoAnalyticsSync and prints the count" do
      expect {
        expect {
          task.invoke(connection.id.to_s, from, to)
        }.to output(/enqueued 2 jobs for connection #{connection.id}/).to_stdout
      }.to change { ChannelAnalyticsSync.jobs.size }.by(1)
        .and change { VideoAnalyticsSync.jobs.size }.by(1)
    end

    it "passes the parsed Date range into the backfill summary line" do
      expect {
        task.invoke(connection.id.to_s, from, to)
      }.to output(/\(#{Date.parse(from)}\.\.#{Date.parse(to)}\)/).to_stdout
    end

    it "exits non-zero with a stderr message when connection_id is empty" do
      expect {
        expect { task.invoke("", from, to) }
          .to raise_error(SystemExit) { |e| expect(e.status).not_to eq(0) }
      }.to output(/connection_id required/).to_stderr
    end

    it "exits non-zero with a stderr message when no YoutubeConnection matches the id" do
      missing_id = (YoutubeConnection.maximum(:id).to_i + 9999).to_s
      expect {
        expect { task.invoke(missing_id, from, to) }
          .to raise_error(SystemExit) { |e| expect(e.status).not_to eq(0) }
      }.to output(/no YoutubeConnection with id=#{missing_id}/).to_stderr
    end

    it "exits non-zero with a stderr message when from is empty" do
      expect {
        expect { task.invoke(connection.id.to_s, "", to) }
          .to raise_error(SystemExit) { |e| expect(e.status).not_to eq(0) }
      }.to output(/from required/).to_stderr
    end

    it "exits non-zero with a stderr message when to is empty" do
      expect {
        expect { task.invoke(connection.id.to_s, from, "") }
          .to raise_error(SystemExit) { |e| expect(e.status).not_to eq(0) }
      }.to output(/to required/).to_stderr
    end

    it "propagates ArgumentError when from > to (backfill service guard)" do
      expect {
        task.invoke(connection.id.to_s, to, from)
      }.to raise_error(ArgumentError, /from must be <= to/)
    end

    it "propagates ArgumentError when the connection needs_reauth" do
      connection.update_columns(needs_reauth: true)
      expect {
        task.invoke(connection.id.to_s, from, to)
      }.to raise_error(ArgumentError, /not active/)
    end

    it "raises Date::Error when a date string is malformed" do
      expect {
        task.invoke(connection.id.to_s, "not-a-date", to)
      }.to raise_error(Date::Error)
    end
  end
end
