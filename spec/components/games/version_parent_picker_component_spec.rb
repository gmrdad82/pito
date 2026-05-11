require "rails_helper"

# Phase 28 §01a — version-parent typeahead picker.
RSpec.describe Games::VersionParentPickerComponent, type: :component do
  let(:game) { create(:game, title: "Pragmata Deluxe") }

  # `form_with` needs a controller view context to resolve the form
  # builder. Use a fake controller-style helper to construct one.
  def with_form(record)
    helper = ActionController::Base.new.view_context
    helper.form_with(model: record, url: "/games/#{record.id}") do |form|
      render_inline(described_class.new(game: record, form: form))
    end
  end

  describe "input rendering" do
    before { with_form(game) }

    it "renders the search input" do
      expect(page).to have_css("input.version-parent-picker-input")
    end

    it "renders the hidden id field" do
      expect(page).to have_css('input[type="hidden"][name="game[version_parent_id]"]', visible: :all)
    end

    it "wires the Stimulus controller" do
      expect(page).to have_css('div[data-controller="version-parent-picker"]')
    end
  end

  describe "pre-filled state when a parent is set" do
    let(:primary) { create(:game, title: "Pragmata") }
    let(:edition) { create(:game, title: "Pragmata Deluxe", version_parent: primary) }

    before { with_form(edition) }

    it "pre-fills the visible input with the current parent's title" do
      input = page.find("input.version-parent-picker-input")
      expect(input.value).to eq("Pragmata")
    end

    it "renders the [detach] bracketed link" do
      expect(page).to have_link("detach")
    end

    it "carries the current parent id in the hidden field" do
      hidden = page.find('input[name="game[version_parent_id]"]', visible: :all)
      expect(hidden.value).to eq(primary.id.to_s)
    end
  end

  describe "disabled state when the row has editions" do
    let(:primary) { create(:game, title: "Pragmata") }

    before do
      create(:game, version_parent: primary)
      with_form(primary)
    end

    it "marks the input disabled" do
      expect(page).to have_css("input.version-parent-picker-input[disabled]")
    end
  end

  describe "empty state when no parent is set" do
    before { with_form(game) }

    it "does NOT render the [detach] link" do
      expect(page).not_to have_link("detach")
    end

    it "carries an empty hidden id" do
      hidden = page.find('input[name="game[version_parent_id]"]', visible: :all)
      expect(hidden.value).to be_blank
    end
  end

  describe "hard rules" do
    before { with_form(game) }

    it "never emits data-turbo-confirm" do
      expect(page.native.to_html).not_to include("data-turbo-confirm")
    end

    it "never references window.confirm or alert" do
      html = page.native.to_html
      expect(html).not_to include("window.confirm")
      expect(html).not_to include("window.alert")
      expect(html).not_to include("window.prompt")
    end
  end
end
