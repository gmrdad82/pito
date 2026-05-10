require "rails_helper"

RSpec.describe NotificationFormatter::Templates::VideoPrePublishCheckMissed do
  let(:payload) do
    {
      "video_id"       => 42,
      "video_title"    => "Recipe stream",
      "missing_checks" => %w[game age paid_promotion]
    }
  end
  let(:notification) do
    create(:notification, :video_pre_publish_check_missed, event_payload: payload)
  end
  let(:template) { described_class.new(notification) }

  describe "#title" do
    it "is `missed pre-publish check: <video_title>`" do
      expect(template.title).to eq("missed pre-publish check: Recipe stream")
    end
  end

  describe "#body" do
    it "lists the missing checks" do
      expect(template.body).to include("game, age, paid_promotion")
    end

    it "links to the edit page" do
      expect(template.body).to include("[review](/videos/42/edit)")
    end

    it "falls back gracefully when missing_checks is empty" do
      n = create(:notification, :video_pre_publish_check_missed,
                 event_payload: payload.merge("missing_checks" => []))
      expect(described_class.new(n).body).to include("(missing checks unavailable)")
    end
  end

  describe "#url" do
    it "is /videos/<id>/edit" do
      expect(template.url).to eq("/videos/42/edit")
    end

    it "is nil when video_id is missing" do
      n = create(:notification, :video_pre_publish_check_missed,
                 event_payload: payload.except("video_id"))
      expect(described_class.new(n).url).to be_nil
    end
  end

  it "is graceful with empty event_payload" do
    n = build(:notification, :video_pre_publish_check_missed, event_payload: {})
    n.save!
    t = described_class.new(n)
    expect { t.title }.not_to raise_error
    expect { t.body }.not_to raise_error
    expect { t.url }.not_to raise_error
  end
end
