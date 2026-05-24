require "rails_helper"

RSpec.describe Pito::Stack::AssetsSubPanelComponent, type: :component do
  let(:writable_status)   { { present: true, writable: true, path: "/assets", size_bytes: 1024, file_count: 10 } }
  let(:read_only_status)  { { present: true, writable: false, path: "/assets", size_bytes: 1024, file_count: 10 } }
  let(:absent_status)     { { present: false, writable: false, path: nil, size_bytes: 0, file_count: 0 } }

  describe "hint line — writable" do
    before do
      render_inline(described_class.new(storage_status: writable_status, breakdown: []))
    end

    it "renders the hint label 'Assets'" do
      expect(page).to have_css(".pito-sub-panel__hint-label", text: "Assets")
    end

    it "renders the status word 'writable'" do
      expect(page).to have_css(".pito-sub-panel__hint-status", text: "writable")
    end

    it "applies is-success class when writable" do
      expect(page).to have_css(".pito-sub-panel__hint-status.is-success")
    end

    it "does not render a Tui::ChipComponent in the title actions" do
      expect(page).not_to have_css(".tui-chip")
    end
  end

  describe "hint line — read-only (present but not writable)" do
    before do
      render_inline(described_class.new(storage_status: read_only_status, breakdown: []))
    end

    it "renders the status word 'not writable'" do
      expect(page).to have_css(".pito-sub-panel__hint-status", text: "not writable")
    end

    it "applies is-danger class when read-only" do
      expect(page).to have_css(".pito-sub-panel__hint-status.is-danger")
    end
  end

  describe "hint line — absent (directory missing)" do
    before do
      render_inline(described_class.new(storage_status: absent_status, breakdown: []))
    end

    it "renders the status word 'not writable'" do
      expect(page).to have_css(".pito-sub-panel__hint-status", text: "not writable")
    end

    it "applies is-danger class when absent" do
      expect(page).to have_css(".pito-sub-panel__hint-status.is-danger")
    end
  end

  describe "#status_word" do
    it "returns 'writable' when present and writable" do
      component = described_class.new(storage_status: writable_status, breakdown: [])
      expect(component.status_word).to eq("writable")
    end

    it "returns 'not writable' when present but not writable" do
      component = described_class.new(storage_status: read_only_status, breakdown: [])
      expect(component.status_word).to eq("not writable")
    end

    it "returns 'not writable' when absent" do
      component = described_class.new(storage_status: absent_status, breakdown: [])
      expect(component.status_word).to eq("not writable")
    end
  end

  describe "#status_color_class" do
    it "returns 'is-success' when writable" do
      component = described_class.new(storage_status: writable_status, breakdown: [])
      expect(component.status_color_class).to eq("is-success")
    end

    it "returns 'is-danger' when read-only" do
      component = described_class.new(storage_status: read_only_status, breakdown: [])
      expect(component.status_color_class).to eq("is-danger")
    end

    it "returns 'is-danger' when absent" do
      component = described_class.new(storage_status: absent_status, breakdown: [])
      expect(component.status_color_class).to eq("is-danger")
    end
  end

  describe "hint line renders before breakdown table" do
    let(:breakdown) do
      [ { label: "Cover arts", file_count: 5, size_bytes: 512 } ]
    end

    before do
      render_inline(described_class.new(storage_status: writable_status, breakdown: breakdown))
    end

    it "renders the hint paragraph" do
      expect(page).to have_css("p.pito-sub-panel__hint")
    end

    it "renders the breakdown table" do
      expect(page).to have_css("table.tui-table")
    end
  end
end
