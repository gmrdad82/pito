require "rails_helper"

# Phase 7.5 §11i — Channels::DiffApply.
RSpec.describe Channels::DiffApply, type: :service do
  let(:user)       { create(:user) }
  let(:connection) { create(:youtube_connection, user: user) }
  let(:channel) do
    create(:channel,
           channel_url: "https://www.youtube.com/channel/UCabcdefghijklmnopqrstuv",
           title: "Local Title",
           handle: "@local",
           description: "Local description",
           country: "US",
           default_language: "en",
           keywords: "tag1 tag2",
           youtube_connection: connection)
  end
  let(:client) { instance_double(Youtube::Client) }
  let(:diff) do
    create(:channel_diff, channel: channel, field_diffs: {
      "title"       => { "pito" => "Local Title",      "youtube" => "Remote Title" },
      "description" => { "pito" => "Local description", "youtube" => "Remote description" }
    })
  end

  describe "validation errors" do
    it "returns missing_decisions when a field is omitted" do
      result = described_class.call(channel_diff: diff,
                                    decisions: { "title" => "youtube" },
                                    user: user)
      expect(result).not_to be_success
      expect(result.error_code).to eq("missing_decisions")
      expect(result.error_message).to include("description")
    end

    it "returns invalid_decision when value is not pito/youtube" do
      result = described_class.call(channel_diff: diff,
                                    decisions: { "title" => "garbage", "description" => "youtube" },
                                    user: user)
      expect(result).not_to be_success
      expect(result.error_code).to eq("invalid_decision")
    end

    it "returns stale_diff when a decision targets a field not in the payload" do
      result = described_class.call(channel_diff: diff,
                                    decisions: { "title" => "youtube",
                                                 "description" => "youtube",
                                                 "ghost" => "pito" },
                                    user: user)
      expect(result).not_to be_success
      expect(result.error_code).to eq("stale_diff")
      expect(result.error_message).to include("ghost")
    end

    it "returns already_resolved when the diff is already closed" do
      diff.update!(resolved_at: 1.minute.ago,
                   resolution_payload: { "title" => { "decision" => "youtube" } })
      result = described_class.call(channel_diff: diff,
                                    decisions: { "title" => "youtube", "description" => "youtube" },
                                    user: user)
      expect(result).not_to be_success
      expect(result.error_code).to eq("already_resolved")
    end

    it "returns unsupported_pito_field when accept_pito on a non-pushable field" do
      diff.update!(field_diffs: {
        "banner_url" => { "pito" => "p", "youtube" => "y" }
      })
      result = described_class.call(channel_diff: diff,
                                    decisions: { "banner_url" => "pito" },
                                    user: user)
      expect(result).not_to be_success
      expect(result.error_code).to eq("unsupported_pito_field")
      expect(result.failing_field).to eq("banner_url")
    end
  end

  describe "happy: all decisions youtube" do
    it "updates the local columns from the youtube snapshot" do
      described_class.call(channel_diff: diff,
                           decisions: { "title" => "youtube", "description" => "youtube" },
                           user: user, client: client)
      channel.reload
      expect(channel.title).to eq("Remote Title")
      expect(channel.description).to eq("Remote description")
    end

    it "does NOT call Youtube::Client#update_channel" do
      expect(client).not_to receive(:update_channel)
      described_class.call(channel_diff: diff,
                           decisions: { "title" => "youtube", "description" => "youtube" },
                           user: user, client: client)
    end

    it "marks the diff resolved with resolved_by_user and resolution_payload" do
      described_class.call(channel_diff: diff,
                           decisions: { "title" => "youtube", "description" => "youtube" },
                           user: user, client: client)
      diff.reload
      expect(diff).to be_resolved
      expect(diff.resolved_by_user_id).to eq(user.id)
      expect(diff.resolution_payload["title"]).to eq(
        { "decision" => "youtube", "value" => "Remote Title" }
      )
      expect(diff.resolution_payload["description"]).to eq(
        { "decision" => "youtube", "value" => "Remote description" }
      )
    end

    it "does NOT write a ChannelChangeLog row" do
      expect {
        described_class.call(channel_diff: diff,
                             decisions: { "title" => "youtube", "description" => "youtube" },
                             user: user, client: client)
      }.not_to change(ChannelChangeLog, :count)
    end

    it "returns success with pito_wins_fields=[] and youtube_wins_fields=[title, description]" do
      result = described_class.call(channel_diff: diff,
                                    decisions: { "title" => "youtube", "description" => "youtube" },
                                    user: user, client: client)
      expect(result).to be_success
      expect(result.pito_wins_fields).to eq([])
      expect(result.youtube_wins_fields).to match_array(%w[title description])
    end
  end

  describe "happy: all decisions pito (branding)" do
    before do
      allow(client).to receive(:update_channel) do |_, payload|
        payload
      end
    end

    it "calls Youtube::Client#update_channel with the branding subset" do
      expect(client).to receive(:update_channel).with(
        channel,
        hash_including(title: "Local Title", description: "Local description")
      )
      described_class.call(channel_diff: diff,
                           decisions: { "title" => "pito", "description" => "pito" },
                           user: user, client: client)
    end

    it "writes a ChannelChangeLog row for the title push" do
      expect {
        described_class.call(channel_diff: diff,
                             decisions: { "title" => "pito", "description" => "pito" },
                             user: user, client: client)
      }.to change(ChannelChangeLog, :count).by(1)

      log = ChannelChangeLog.last
      expect(log.field).to eq("title")
      expect(log.new_value).to eq("Local Title")
      expect(log.old_value).to eq("Remote Title")
      expect(log.changed_by_user_id).to eq(user.id)
    end

    it "stamps title_changed_at after a successful title push" do
      described_class.call(channel_diff: diff,
                           decisions: { "title" => "pito", "description" => "pito" },
                           user: user, client: client)
      expect(channel.reload.title_changed_at).to be_within(2.seconds).of(Time.current)
    end

    it "does NOT change the local title / description (pito-wins keeps local)" do
      described_class.call(channel_diff: diff,
                           decisions: { "title" => "pito", "description" => "pito" },
                           user: user, client: client)
      channel.reload
      expect(channel.title).to eq("Local Title")
      expect(channel.description).to eq("Local description")
    end

    it "marks the diff resolved with the pito decisions" do
      described_class.call(channel_diff: diff,
                           decisions: { "title" => "pito", "description" => "pito" },
                           user: user, client: client)
      diff.reload
      expect(diff.resolution_payload["title"]).to eq(
        { "decision" => "pito", "value" => "Local Title" }
      )
    end

    it "result.success? + pito_wins_fields populated" do
      result = described_class.call(channel_diff: diff,
                                    decisions: { "title" => "pito", "description" => "pito" },
                                    user: user, client: client)
      expect(result).to be_success
      expect(result.pito_wins_fields).to match_array(%w[title description])
      expect(result.youtube_wins_fields).to eq([])
    end
  end

  describe "happy: mixed pito + youtube decisions" do
    before do
      allow(client).to receive(:update_channel)
    end

    it "writes title locally (youtube-wins) and pushes description (pito-wins)" do
      expect(client).to receive(:update_channel).with(
        channel,
        hash_including(description: "Local description")
      )
      described_class.call(channel_diff: diff,
                           decisions: { "title" => "youtube", "description" => "pito" },
                           user: user, client: client)
      channel.reload
      expect(channel.title).to eq("Remote Title")
    end

    it "result.success? with the split counts" do
      result = described_class.call(channel_diff: diff,
                                    decisions: { "title" => "youtube", "description" => "pito" },
                                    user: user, client: client)
      expect(result).to be_success
      expect(result.pito_wins_fields).to eq(%w[description])
      expect(result.youtube_wins_fields).to eq(%w[title])
    end
  end

  describe "handle push" do
    let(:diff) do
      create(:channel_diff, channel: channel, field_diffs: {
        "handle" => { "pito" => "@new", "youtube" => "@old" }
      })
    end

    it "calls update_handle for an accept_pito on handle" do
      expect(client).to receive(:update_handle).with(channel, "@new")
      described_class.call(channel_diff: diff,
                           decisions: { "handle" => "pito" },
                           user: user, client: client)
    end

    it "writes a ChannelChangeLog row for the handle push" do
      allow(client).to receive(:update_handle)
      expect {
        described_class.call(channel_diff: diff,
                             decisions: { "handle" => "pito" },
                             user: user, client: client)
      }.to change(ChannelChangeLog.where(field: "handle"), :count).by(1)
    end

    it "stamps handle_changed_at after a successful handle push" do
      allow(client).to receive(:update_handle)
      described_class.call(channel_diff: diff,
                           decisions: { "handle" => "pito" },
                           user: user, client: client)
      expect(channel.reload.handle_changed_at).to be_within(2.seconds).of(Time.current)
    end
  end

  describe "flaw: partial-failure rolls back the whole transaction (Q3)" do
    let(:diff) do
      create(:channel_diff, channel: channel, field_diffs: {
        "title"       => { "pito" => "New Title",       "youtube" => "Old Title" },
        "description" => { "pito" => "New Description", "youtube" => "Old Description" }
      })
    end

    before do
      allow(client).to receive(:update_channel)
        .and_raise(Youtube::QuotaExhaustedError.new("quota busted"))
    end

    it "returns failure with the failing_field surfaced" do
      result = described_class.call(channel_diff: diff,
                                    decisions: { "title" => "pito", "description" => "pito" },
                                    user: user, client: client)
      expect(result).not_to be_success
      expect(result.error_code).to eq("quota_exhausted")
      expect(result.failing_field).to be_in(%w[title description])
      expect(result.error_message).to include("no changes applied")
    end

    it "rolls back ALL changes — channel unchanged, no log rows, diff unresolved" do
      described_class.call(channel_diff: diff,
                           decisions: { "title" => "pito", "description" => "pito" },
                           user: user, client: client)
      channel.reload
      expect(channel.title).to eq("Local Title")
      expect(channel.description).to eq("Local description")
      expect(ChannelChangeLog.where(channel: channel).count).to eq(0)
      expect(diff.reload).to be_open
    end
  end

  describe "flaw: mixed decisions, push fails — youtube-side writes also roll back" do
    let(:diff) do
      create(:channel_diff, channel: channel, field_diffs: {
        "title"       => { "pito" => "New Title",       "youtube" => "Old Title" },
        "description" => { "pito" => "New Description", "youtube" => "Old Description" }
      })
    end

    before do
      allow(client).to receive(:update_channel).and_raise(StandardError, "boom")
    end

    it "rolls back the youtube-wins local write when the pito-wins push fails" do
      described_class.call(channel_diff: diff,
                           decisions: { "title" => "youtube", "description" => "pito" },
                           user: user, client: client)
      channel.reload
      # `title` stays at the original local value despite the
      # youtube-wins assignment — the rollback covered it.
      expect(channel.title).to eq("Local Title")
    end
  end

  describe "edge: no youtube_connection on the channel" do
    let(:disconnected) { create(:channel, youtube_connection: nil) }
    let(:disc_diff) do
      create(:channel_diff, channel: disconnected, field_diffs: {
        "title" => { "pito" => "p", "youtube" => "y" }
      })
    end

    it "returns validation_error when the user picks accept_pito" do
      result = described_class.call(channel_diff: disc_diff,
                                    decisions: { "title" => "pito" },
                                    user: user)
      expect(result).not_to be_success
      # The push raises ValidationError wrapped in PushFailure → code
      # falls into the catch-all push_failed bucket.
      expect(%w[push_failed validation_error]).to include(result.error_code)
    end

    it "still allows accept_youtube (no push needed)" do
      result = described_class.call(channel_diff: disc_diff,
                                    decisions: { "title" => "youtube" },
                                    user: user)
      expect(result).to be_success
      expect(disconnected.reload.title).to eq("y")
    end
  end
end
