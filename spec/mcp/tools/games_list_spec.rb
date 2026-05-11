require "rails_helper"
require_relative "../../../app/mcp/tools/games_list"

# Phase 28 §01a — `games_list` MCP tool. Default = primaries only.
# `include_editions: "yes"` flips the listing to a flat set.
RSpec.describe Mcp::Tools::GamesList do
  let!(:primary)  { create(:game, title: "Pragmata") }
  let!(:edition)  { create(:game, title: "Pragmata Deluxe", version_parent: primary, version_title: "Deluxe") }
  let!(:other)    { create(:game, title: "Halo 3") }

  def parsed(response)
    JSON.parse(response.content.first[:text])
  end

  describe "default behaviour (primaries only)" do
    it "omits editions when include_editions is absent" do
      result = described_class.call
      payload = parsed(result)
      titles = payload["games"].map { |g| g["title"] }
      expect(titles).to include("Pragmata", "Halo 3")
      expect(titles).not_to include("Pragmata Deluxe")
    end

    it "echoes include_editions: \"no\" in the response" do
      result = described_class.call
      expect(parsed(result)["include_editions"]).to eq("no")
    end

    it "stamps editions_count on a primary with editions" do
      result = described_class.call
      payload = parsed(result)
      row = payload["games"].find { |g| g["title"] == "Pragmata" }
      expect(row["editions_count"]).to eq(1)
    end

    it "stamps editions_count = 0 on a primary with no editions" do
      result = described_class.call
      payload = parsed(result)
      row = payload["games"].find { |g| g["title"] == "Halo 3" }
      expect(row["editions_count"]).to eq(0)
    end
  end

  describe "include_editions: \"yes\"" do
    it "returns the flat list" do
      result = described_class.call(include_editions: "yes")
      payload = parsed(result)
      titles = payload["games"].map { |g| g["title"] }
      expect(titles).to include("Pragmata", "Pragmata Deluxe", "Halo 3")
    end

    it "echoes include_editions: \"yes\" in the response" do
      result = described_class.call(include_editions: "yes")
      expect(parsed(result)["include_editions"]).to eq("yes")
    end

    it "carries version_parent_id + version_title on edition rows" do
      result = described_class.call(include_editions: "yes")
      payload = parsed(result)
      row = payload["games"].find { |g| g["title"] == "Pragmata Deluxe" }
      expect(row["version_parent_id"]).to eq(primary.id)
      expect(row["version_title"]).to eq("Deluxe")
    end
  end

  describe "include_editions: \"no\" (explicit)" do
    it "behaves identically to omitting the parameter" do
      result = described_class.call(include_editions: "no")
      payload = parsed(result)
      titles = payload["games"].map { |g| g["title"] }
      expect(titles).not_to include("Pragmata Deluxe")
    end
  end

  describe "yes/no boundary enforcement" do
    it "rejects \"true\" with a clear error" do
      result = described_class.call(include_editions: "true")
      expect(result.to_h[:isError]).to be(true)
      expect(result.content.first[:text]).to include("yes")
    end

    it "rejects \"1\" with a clear error" do
      result = described_class.call(include_editions: "1")
      expect(result.to_h[:isError]).to be(true)
    end

    it "rejects \"false\" with a clear error" do
      result = described_class.call(include_editions: "false")
      expect(result.to_h[:isError]).to be(true)
    end
  end

  describe "pagination" do
    it "honors per_page cap (max 100)" do
      result = described_class.call(per_page: 500)
      payload = parsed(result)
      expect(payload["pagination"]["per_page"]).to eq(100)
    end

    it "defaults to page 1 + per_page 25" do
      result = described_class.call
      payload = parsed(result)
      expect(payload["pagination"]["page"]).to eq(1)
      expect(payload["pagination"]["per_page"]).to eq(25)
    end

    it "reports total + total_pages" do
      result = described_class.call
      payload = parsed(result)
      # Primaries only: Pragmata + Halo 3 = 2
      expect(payload["pagination"]["total"]).to eq(2)
    end
  end

  describe "auth gating" do
    it "is gated on app scope" do
      record, _plaintext = ApiToken.generate!(
        user: User.first || create(:user),
        name: "dev-only", scopes: [ Scopes::DEV ]
      )
      Current.token = record
      result = described_class.call
      expect(result.to_h[:isError]).to be(true)
      expect(result.content.first[:text]).to include("insufficient_scope")
    end
  end

  describe "schema" do
    it "declares additionalProperties false" do
      schema = described_class.input_schema.to_h
      expect(schema[:additionalProperties]).to eq(false).or eq("false")
    end

    it "describes the yes/no enum for include_editions" do
      schema = described_class.input_schema.to_h
      expect(schema.dig(:properties, :include_editions, :enum)).to eq(%w[yes no])
    end
  end
end
