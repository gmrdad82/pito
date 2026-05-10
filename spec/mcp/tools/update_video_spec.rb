require "rails_helper"
require_relative "../../../app/mcp/tools/update_video"

# Phase 12 — update_video covers the full writable subset (title,
# description, tags, category_id, project_id, made_for_kids,
# synthetic_media, star). NOT a publish path — privacy_status and
# publish_at flow through publish_video.
RSpec.describe Mcp::Tools::UpdateVideo do
  let!(:channel) { create(:channel) }

  it "applies title with confirm: yes" do
    v = create(:video, channel: channel, title: "old")
    described_class.call(id: v.id, title: "new title", confirm: "yes")
    expect(v.reload.title).to eq("new title")
  end

  it "applies description" do
    v = create(:video, channel: channel)
    described_class.call(id: v.id, description: "fresh", confirm: "yes")
    expect(v.reload.description).to eq("fresh")
  end

  it "applies tags array" do
    v = create(:video, channel: channel)
    described_class.call(id: v.id, tags: %w[gaming halo], confirm: "yes")
    expect(v.reload.tags).to eq(%w[gaming halo])
  end

  it "applies category_id" do
    v = create(:video, channel: channel)
    described_class.call(id: v.id, category_id: "22", confirm: "yes")
    expect(v.reload.category_id).to eq("22")
  end

  it "applies project_id" do
    v = create(:video, channel: channel)
    p = create(:project)
    described_class.call(id: v.id, project_id: p.id, confirm: "yes")
    expect(v.reload.project_id).to eq(p.id)
  end

  it "applies self_declared_made_for_kids" do
    v = create(:video, channel: channel)
    described_class.call(id: v.id, self_declared_made_for_kids: "yes", confirm: "yes")
    expect(v.reload.self_declared_made_for_kids).to be(true)
  end

  it "applies contains_synthetic_media" do
    v = create(:video, channel: channel)
    described_class.call(id: v.id, contains_synthetic_media: "yes", confirm: "yes")
    expect(v.reload.contains_synthetic_media).to be(true)
  end

  it "applies star=yes" do
    v = create(:video, channel: channel, star: false)
    described_class.call(id: v.id, star: "yes", confirm: "yes")
    expect(v.reload.star?).to be(true)
  end

  it "rejects star=true (raw boolean)" do
    v = create(:video, channel: channel)
    result = described_class.call(id: v.id, star: true, confirm: "yes")
    expect(result.to_h[:isError]).to be true
  end

  it "returns dry-run preview when confirm=no" do
    v = create(:video, channel: channel, title: "old")
    result = described_class.call(id: v.id, title: "new", confirm: "no")
    text = result.content.first[:text]
    expect(text).to include("changes")
    expect(text).to include("old")
    expect(text).to include("new")
    expect(v.reload.title).to eq("old") # NOT mutated
  end

  it "returns dry-run preview when confirm omitted (defaults to no)" do
    v = create(:video, channel: channel, title: "old")
    described_class.call(id: v.id, title: "new")
    expect(v.reload.title).to eq("old")
  end

  it "returns error for missing video" do
    result = described_class.call(id: 99999, title: "x", confirm: "yes")
    expect(result.to_h[:isError]).to be true
  end

  it "returns error when no fields given" do
    v = create(:video, channel: channel)
    result = described_class.call(id: v.id, confirm: "yes")
    expect(result.to_h[:isError]).to be true
    expect(result.content.first[:text]).to include("no fields")
  end

  it "rejects privacy_status with explicit error" do
    v = create(:video, channel: channel)
    result = described_class.call(id: v.id, privacy_status: "public", confirm: "yes")
    expect(result.to_h[:isError]).to be true
    expect(result.content.first[:text]).to include("privacy_status")
  end

  it "rejects publish_at with explicit error" do
    v = create(:video, channel: channel)
    result = described_class.call(id: v.id, publish_at: 1.day.from_now.iso8601, confirm: "yes")
    expect(result.to_h[:isError]).to be true
  end

  describe "scope gate" do
    it "returns insufficient_scope when token lacks `app`" do
      record, _plaintext = ApiToken.generate!(
        user: User.first || create(:user),
        name: "dev-only",
        scopes: [ Scopes::DEV ]
      )
      Current.token = record

      v = create(:video, channel: channel)
      result = described_class.call(id: v.id, title: "x", confirm: "yes")
      expect(result.to_h[:isError]).to be true
      expect(result.content.first[:text]).to include("insufficient_scope")
    end
  end

  describe "input schema" do
    it "additionalProperties is false" do
      schema = described_class.input_schema.to_h
      expect(schema[:additionalProperties]).to eq(false).or eq("false")
    end

    it "declares confirm with yes/no enum" do
      schema = described_class.input_schema.to_h
      props = schema[:properties] || schema["properties"]
      confirm = props[:confirm] || props["confirm"]
      enum = confirm[:enum] || confirm["enum"]
      expect(enum.map(&:to_s)).to contain_exactly("yes", "no")
    end
  end
end
