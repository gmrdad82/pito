# frozen_string_literal: true

require "rails_helper"

RSpec.describe Video::EmbedText do
  it "joins title, description, tags, and category (em-dash, blank-skipped)" do
    video = build(
      :video,
      title:       "Lies of P — Boss Guide",
      description: "Every boss, ranked.",
      tags:        %w[soulslike bosses],
      category_id: "20"
    )

    text = described_class.call(video)

    expect(text).to include("Lies of P — Boss Guide")
    expect(text).to include("Every boss, ranked.")
    expect(text).to include("tags: soulslike, bosses")
    expect(text).to include("category: Gaming")
  end

  it "skips blank slots" do
    video = build(:video, title: "Just a title", description: nil, tags: [], category_id: nil)
    expect(described_class.call(video)).to eq("Just a title")
  end

  it "omits an unknown category id" do
    video = build(:video, title: "T", category_id: "9999", tags: [], description: nil)
    expect(described_class.call(video)).not_to include("category:")
  end
end
