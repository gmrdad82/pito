require "rails_helper"

RSpec.describe "Footages", type: :request do
  let!(:project) { create(:project) }
  let!(:footage) { create(:footage, project: project) }

  # Keyboard-navigation opt-in (2026-05-10): each footage row on the
  # index carries `data-keyboard-row` + `data-keyboard-row-id` so the
  # global keyboard controller's `j`/`k` highlight resolves against the
  # row's footage id. Footage has no per-row bulk action on this surface
  # yet, but the highlight still helps scan through the list.
  describe "GET /footages (index keyboard-row markup)" do
    let!(:other_footage) { create(:footage, project: project) }

    it "tags each footage row with data-keyboard-row + data-keyboard-row-id" do
      get footages_path
      html = Nokogiri::HTML.fragment(response.body)
      rows = html.css("tbody tr[data-keyboard-row]")
      expect(rows.size).to eq(2)
      ids = rows.map { |r| r["data-keyboard-row-id"] }.sort
      expect(ids).to eq([ footage.id.to_s, other_footage.id.to_s ].sort)
    end

    it "leaves the empty-state body without keyboard-row markup" do
      Footage.delete_all
      get footages_path
      expect(response.body).not_to include("data-keyboard-row")
    end
  end

  describe "GET /footages/:id/edit" do
    it "returns 200 (HTML)" do
      get edit_footage_path(footage)
      expect(response).to have_http_status(:ok)
    end

    it "renders the footage filename in the heading" do
      footage.update!(filename: "clip.mkv")
      get edit_footage_path(footage)
      expect(response.body).to include("clip.mkv")
    end

    # 2026-05-11 form-pane sweep — the edit form sits inside
    # `.pane.pane--standalone` like every other standalone edit page.
    it "wraps the edit form in a .pane.pane--standalone" do
      get edit_footage_path(footage)
      html = Nokogiri::HTML.fragment(response.body)
      pane = html.at_css("div.pane.pane--standalone")
      expect(pane).not_to be_nil
      expect(pane.at_css('select[name="footage[kind]"]')).not_to be_nil
    end
  end

  describe "GET /footages/:id" do
    it "returns 200 (HTML)" do
      get footage_path(footage)
      expect(response).to have_http_status(:ok)
    end

    it "returns JSON with yes/no booleans" do
      get footage_path(footage), as: :json
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["has_commentary_track"]).to eq("no")
    end

    it "serializes fps as a JSON number (matching Rust CLI's Option<f64>)" do
      footage.update!(fps: BigDecimal("60.0"))
      get footage_path(footage), as: :json
      body = JSON.parse(response.body)
      expect(body["fps"]).to be_a(Numeric)
      expect(body["fps"]).to eq(60.0)
    end

    it "serializes fps as null when nil" do
      footage.update!(fps: nil)
      get footage_path(footage), as: :json
      body = JSON.parse(response.body)
      expect(body["fps"]).to be_nil
    end

    it "serializes filesize_bytes as null for rows the importer hasn't probed" do
      get footage_path(footage), as: :json
      body = JSON.parse(response.body)
      expect(body).to have_key("filesize_bytes")
      expect(body["filesize_bytes"]).to be_nil
    end

    it "serializes filesize_bytes as the raw integer (not the human string)" do
      footage.update!(filesize_bytes: 12_345)
      get footage_path(footage), as: :json
      body = JSON.parse(response.body)
      expect(body["filesize_bytes"]).to eq(12_345)
    end

    # Phase 7.5 §06 — Scrub layout. The HTML show page renders a
    # `data-controller="footage-scrub"` container with the manifest URL,
    # master / thumb URL templates, and the duration value. Stimulus
    # picks it up client-side; we assert the markup is present so a
    # template regression is caught at the request-spec level.
    it "renders the footage-scrub Stimulus container in the HTML show page" do
      get footage_path(footage)
      expect(response.body).to include('data-controller="footage-scrub"')
      expect(response.body).to include('data-footage-scrub-manifest-url-value')
      expect(response.body).to include('data-footage-scrub-master-url-template-value')
      expect(response.body).to include('data-footage-scrub-thumb-url-template-value')
    end
  end

  describe "PATCH /footages/:id" do
    it "accepts HTML form-encoded edit fields" do
      patch footage_path(footage), params: { footage: { description: "new description" } }
      expect(footage.reload.description).to eq("new description")
    end
  end

  describe "DELETE /footages/:id" do
    it "destroys the footage (HTML)" do
      expect {
        delete footage_path(footage)
      }.to change(Footage, :count).by(-1)
    end
  end
end
