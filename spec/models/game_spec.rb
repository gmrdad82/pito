require "rails_helper"

# Phase 8 — tenant drop. Game is install-wide.
RSpec.describe Game, type: :model do
  subject { build(:game) }

  describe "associations" do
    it { is_expected.to belong_to(:collection).optional }
    it { is_expected.to have_many(:footages).dependent(:nullify) }
    it "does not declare a tenant association" do
      expect(Game.reflect_on_association(:tenant)).to be_nil
    end

    it "has_one_attached :cover_art" do
      expect(Game.new).to respond_to(:cover_art)
    end
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:title) }
    it { is_expected.to validate_length_of(:title).is_at_most(255) }
  end

  describe "default title" do
    it 'defaults to "Untitled game"' do
      game = Game.create!
      expect(game.title).to eq("Untitled game")
    end
  end

  describe "platforms validation" do
    it "accepts the canonical example shape" do
      game = build(:game, platforms: [ { "platform" => "PS5", "owned" => true, "recorded_on" => true } ])
      expect(game).to be_valid
    end

    it "accepts an empty array" do
      game = build(:game, platforms: [])
      expect(game).to be_valid
    end

    Game::ALLOWED_PLATFORMS.each do |platform|
      it "accepts #{platform.inspect}" do
        game = build(:game, platforms: [ { "platform" => platform, "owned" => true, "recorded_on" => false } ])
        expect(game).to be_valid
      end
    end

    it "rejects free-text 'Other'" do
      game = build(:game, platforms: [ { "platform" => "Other", "owned" => true } ])
      expect(game).not_to be_valid
      expect(game.errors[:platforms]).to be_present
    end

    it "rejects a non-array platforms value" do
      game = build(:game, platforms: "PS5")
      expect(game).not_to be_valid
    end

    it "rejects a non-boolean owned flag" do
      game = build(:game, platforms: [ { "platform" => "PS5", "owned" => "yes" } ])
      expect(game).not_to be_valid
    end
  end
end
