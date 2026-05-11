require "rails_helper"

RSpec.describe DiffDecisionRadioComponent, type: :component do
  it "renders both radios with the bracketed convention labels" do
    render_inline(described_class.new(field: "title"))
    expect(page).to have_css('input[type="radio"][name="decisions[title]"][value="pito"]')
    expect(page).to have_css('input[type="radio"][name="decisions[title]"][value="youtube"]')
    expect(page).to have_text("accept pito")
    expect(page).to have_text("accept youtube")
  end

  it "defaults to accept youtube checked" do
    render_inline(described_class.new(field: "title"))
    expect(page).to have_css('input[value="youtube"][checked]')
    expect(page).to have_no_css('input[value="pito"][checked]')
  end

  it "honours the selected: kwarg" do
    render_inline(described_class.new(field: "title", selected: "pito"))
    expect(page).to have_css('input[value="pito"][checked]')
    expect(page).to have_no_css('input[value="youtube"][checked]')
  end

  it "disables the pito radio + checks youtube when disabled: true" do
    render_inline(described_class.new(field: "view_count", disabled: true))
    expect(page).to have_css('input[value="pito"][disabled]')
    expect(page).to have_css('input[value="youtube"][checked]')
    expect(page).to have_no_css('input[value="pito"][checked]')
    expect(page).to have_text("display-only")
  end

  it "uses the supplied name kwarg for nested forms" do
    render_inline(described_class.new(field: "title", name: "video_diff[decisions]"))
    expect(page).to have_css('input[name="video_diff[decisions][title]"]')
  end

  it "exposes unique input ids per field + value" do
    render_inline(described_class.new(field: "description"))
    expect(page).to have_css('input#decision_description_pito')
    expect(page).to have_css('input#decision_description_youtube')
  end
end
