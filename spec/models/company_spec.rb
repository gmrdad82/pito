# frozen_string_literal: true

require "rails_helper"

RSpec.describe Company, type: :model do
  subject(:company) { build(:company) }

  # ── Associations ─────────────────────────────────────────────────
  describe "associations" do
    it { is_expected.to have_many(:game_developers).dependent(:destroy) }
    it { is_expected.to have_many(:game_publishers).dependent(:destroy) }
    it { is_expected.to have_many(:developed_games).through(:game_developers).source(:game) }
    it { is_expected.to have_many(:published_games).through(:game_publishers).source(:game) }
  end

  # ── Validations ──────────────────────────────────────────────────
  describe "validations" do
    it { is_expected.to validate_presence_of(:igdb_id) }
    it { is_expected.to validate_presence_of(:name) }

    it "requires uniqueness of igdb_id" do
      create(:company, igdb_id: 99_999)
      dup = build(:company, igdb_id: 99_999)
      expect(dup).not_to be_valid
      expect(dup.errors[:igdb_id]).to be_present
    end

    it "rejects non-integer igdb_id" do
      company.igdb_id = 1.5
      expect(company).not_to be_valid
    end

    it "rejects igdb_id of zero" do
      company.igdb_id = 0
      expect(company).not_to be_valid
    end

    it "rejects negative igdb_id" do
      company.igdb_id = -5
      expect(company).not_to be_valid
    end
  end

  # ── Dependent destroy ────────────────────────────────────────────
  describe "dependent destroy" do
    it "destroys game_developers when company is destroyed" do
      company = create(:company)
      create(:game_developer, company: company)

      expect { company.destroy! }.to change(GameDeveloper, :count).by(-1)
    end

    it "destroys game_publishers when company is destroyed" do
      company = create(:company)
      create(:game_publisher, company: company)

      expect { company.destroy! }.to change(GamePublisher, :count).by(-1)
    end
  end
end
