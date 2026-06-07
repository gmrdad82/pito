# frozen_string_literal: true

require "rails_helper"

RSpec.describe Stat do
  it "has a working factory" do
    expect(build(:stat)).to be_valid
  end

  describe "validations" do
    it "requires a kind" do
      stat = build(:stat, kind: nil)
      expect(stat).not_to be_valid
      expect(stat.errors[:kind]).to be_present
    end

    it "rejects a kind outside KINDS" do
      stat = build(:stat, kind: "watched_hours")
      expect(stat).not_to be_valid
      expect(stat.errors[:kind]).to be_present
    end

    it "accepts each allowed kind" do
      Stat::KINDS.each do |kind|
        expect(build(:stat, kind: kind)).to be_valid
      end
    end

    it "enforces uniqueness per (entity, kind)" do
      channel = create(:channel)
      create(:stat, entity: channel, kind: "views")
      dup = build(:stat, entity: channel, kind: "views")
      expect(dup).not_to be_valid
      expect(dup.errors[:entity_id]).to be_present
    end

    it "allows the same kind on different entities" do
      create(:stat, entity: create(:channel), kind: "views")
      expect(build(:stat, entity: create(:channel), kind: "views")).to be_valid
    end

    it "allows different kinds on the same entity" do
      channel = create(:channel)
      create(:stat, entity: channel, kind: "views")
      expect(build(:stat, entity: channel, kind: "subscribers")).to be_valid
    end
  end

  describe "polymorphic entity" do
    it "links to a channel" do
      channel = create(:channel)
      stat = create(:stat, entity: channel)
      expect(stat.entity).to eq(channel)
      expect(stat.entity_type).to eq("Channel")
    end

    it "links to a video" do
      video = create(:video)
      stat = create(:stat, entity: video, kind: "views")
      expect(stat.entity).to eq(video)
    end

    it "links to a game" do
      game = create(:game)
      stat = create(:stat, entity: game, kind: "views")
      expect(stat.entity).to eq(game)
    end
  end
end
