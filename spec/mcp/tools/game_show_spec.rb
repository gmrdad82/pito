require "rails_helper"
require_relative "../../../app/mcp/tools/game_show"

# Phase 28 §01a — `game_show` MCP tool. Returns a single game with
# `version_parent_id`, `version_title`, and an `editions` array
# populated for primaries (empty for editions).
RSpec.describe Mcp::Tools::GameShow do
  let!(:primary) { create(:game, title: "Pragmata", igdb_id: 9000, igdb_slug: "pragmata") }
  let!(:deluxe)  { create(:game, title: "Pragmata Deluxe", version_parent: primary,
                                 version_title: "Deluxe", igdb_id: 9001, igdb_slug: "pragmata-deluxe") }

  def parsed(response)
    JSON.parse(response.content.first[:text])
  end

  describe "by id" do
    it "returns the game" do
      result = described_class.call(id: primary.id.to_s)
      payload = parsed(result)
      expect(payload["id"]).to eq(primary.id)
      expect(payload["title"]).to eq("Pragmata")
    end
  end

  describe "by igdb_slug" do
    it "returns the game" do
      result = described_class.call(id: "pragmata")
      payload = parsed(result)
      expect(payload["title"]).to eq("Pragmata")
    end
  end

  describe "primary response" do
    it "carries version_parent_id = nil for a primary" do
      result = described_class.call(id: primary.id.to_s)
      expect(parsed(result)["version_parent_id"]).to be_nil
    end

    it "carries the editions array populated" do
      result = described_class.call(id: primary.id.to_s)
      payload = parsed(result)
      expect(payload["editions"]).to be_an(Array)
      expect(payload["editions"].size).to eq(1)
    end

    it "renders each edition with id, title, igdb_slug, version_title" do
      result = described_class.call(id: primary.id.to_s)
      payload = parsed(result)
      row = payload["editions"].first
      expect(row).to include(
        "id" => deluxe.id,
        "title" => "Pragmata Deluxe",
        "igdb_slug" => "pragmata-deluxe",
        "version_title" => "Deluxe"
      )
    end
  end

  describe "edition response" do
    it "carries version_parent_id pointing at the primary" do
      result = described_class.call(id: deluxe.id.to_s)
      payload = parsed(result)
      expect(payload["version_parent_id"]).to eq(primary.id)
    end

    it "carries version_title" do
      result = described_class.call(id: deluxe.id.to_s)
      expect(parsed(result)["version_title"]).to eq("Deluxe")
    end

    it "carries an empty editions array (no recursion)" do
      result = described_class.call(id: deluxe.id.to_s)
      expect(parsed(result)["editions"]).to eq([])
    end
  end

  describe "missing record" do
    it "returns an isError response when the id does not exist" do
      result = described_class.call(id: "99999999")
      expect(result.to_h[:isError]).to be(true)
    end

    it "returns an isError response when the id is blank" do
      result = described_class.call(id: "   ")
      expect(result.to_h[:isError]).to be(true)
    end
  end

  describe "auth gating" do
    it "is gated on app scope" do
      record, _plaintext = ApiToken.generate!(
        user: User.first || create(:user),
        name: "dev-only", scopes: [ Scopes::DEV ]
      )
      Current.token = record
      result = described_class.call(id: primary.id.to_s)
      expect(result.to_h[:isError]).to be(true)
      expect(result.content.first[:text]).to include("insufficient_scope")
    end
  end

  describe "schema" do
    it "declares additionalProperties false" do
      schema = described_class.input_schema.to_h
      expect(schema[:additionalProperties]).to eq(false).or eq("false")
    end

    it "requires id" do
      schema = described_class.input_schema.to_h
      expect(schema[:required]).to include("id")
    end
  end
end
