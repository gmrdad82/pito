# frozen_string_literal: true

require "rails_helper"

RSpec.describe VideoPublish, type: :job do
  let(:channel) { create(:channel) }
  let(:video)   { create(:video, channel: channel, privacy_status: :private) }

  # pre_publish_complete? does not yet exist on the Video model (the method is
  # referenced by the job but the column/logic haven't been added yet). We use
  # without_partial_double_verification to stub it until the method ships.
  def stub_pre_publish(returns:)
    without_partial_double_verification do
      allow(video).to receive(:pre_publish_complete?).and_return(returns)
      allow(Video).to receive(:find_by).with(id: video.id).and_return(video)
    end
  end

  describe "#perform" do
    context "when video does not exist" do
      it "is a no-op" do
        expect { described_class.new.perform(0, "public") }.not_to raise_error
      end
    end

    context "when pre_publish_complete? returns false" do
      before { stub_pre_publish(returns: false) }

      it "does not change privacy_status" do
        described_class.new.perform(video.id, "public")
        expect(video.reload.privacy_status).to eq("private")
      end
    end

    context "when pre_publish_complete? returns true" do
      before { stub_pre_publish(returns: true) }

      it "updates privacy_status to public" do
        described_class.new.perform(video.id, "public")
        expect(video.reload.privacy_status).to eq("public")
      end

      it "updates privacy_status to unlisted" do
        described_class.new.perform(video.id, "unlisted")
        expect(video.reload.privacy_status).to eq("unlisted")
      end

      context "with a publish_at timestamp" do
        let(:publish_at) { 1.day.from_now.utc }

        it "stores the UTC instant in publish_at" do
          described_class.new.perform(video.id, "public", publish_at.iso8601)
          video.reload
          expect(video.publish_at).to be_within(1.second).of(publish_at)
        end

        it "keeps privacy_status as private for scheduled publishes" do
          described_class.new.perform(video.id, "public", publish_at.iso8601)
          expect(video.reload.privacy_status).to eq("private")
        end
      end
    end
  end
end
