require "rails_helper"
require_relative "../../../app/mcp/tools/list_saved_views"
require_relative "../../../app/mcp/tools/create_saved_view"
require_relative "../../../app/mcp/tools/delete_saved_view"

RSpec.describe "Saved view tools" do
  describe Mcp::Tools::ListSavedViews do
    it "returns all saved views" do
      create(:saved_view, kind: :channels, name: "my channels")
      create(:saved_view, :videos, name: "my videos")

      result = described_class.call
      data = JSON.parse(result.content.first[:text])

      expect(data.size).to eq(2)
    end

    it "filters by kind" do
      create(:saved_view, kind: :channels, name: "ch view")
      create(:saved_view, :videos, name: "vid view")

      result = described_class.call(kind: "channels")
      data = JSON.parse(result.content.first[:text])

      expect(data.size).to eq(1)
      expect(data.first["kind"]).to eq("channels")
    end
  end

  describe Mcp::Tools::CreateSavedView do
    it "creates a saved view" do
      c1 = create(:channel)
      c2 = create(:channel)

      result = described_class.call(kind: "channels", name: "test view", ids: [ c1.id, c2.id ])

      expect(SavedView.count).to eq(1)
      sv = SavedView.last
      expect(sv.url).to eq("/channels/panes?ids=#{c1.id},#{c2.id}")
      expect(result.content.first[:text]).to include("view saved")
    end

    it "requires at least 2 IDs" do
      result = described_class.call(kind: "channels", name: "test", ids: [ 1 ])
      expect(result.to_h[:isError]).to be true
    end
  end

  describe Mcp::Tools::DeleteSavedView do
    it "deletes a saved view" do
      sv = create(:saved_view, name: "to delete")

      result = described_class.call(id: sv.id)

      expect(SavedView.count).to eq(0)
      expect(result.content.first[:text]).to include("deleted")
    end

    it "returns error for missing view" do
      result = described_class.call(id: 99999)
      expect(result.to_h[:isError]).to be true
    end
  end
end
