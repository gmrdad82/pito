require "rails_helper"

RSpec.describe FilterChipComponent, type: :component do
  it "renders [ ] label when not checked" do
    render_inline(described_class.new(label: "starred", param: "star"))
    expect(page).to have_css("a.filter-chip")
    expect(page).to have_css("span.md-check-static", text: "[ ]")
    expect(page).to have_css("span.md-check-static-label", text: "starred")
  end

  it "renders [x] label when checked" do
    render_inline(described_class.new(label: "starred", param: "star", current_params: { "star" => "yes" }))
    expect(page).to have_css("span.md-check-static", text: "[x]")
    expect(page).to have_css("span.md-check-static-label", text: "starred")
  end

  it "treats symbol keys in current_params equivalently to string keys" do
    render_inline(described_class.new(label: "starred", param: "star", current_params: { star: "yes" }))
    expect(page).to have_css("span.md-check-static", text: "[x]")
  end

  it "generates an href that adds the param when toggling on" do
    render_inline(described_class.new(label: "starred", param: "star"))
    expect(page).to have_css('a.filter-chip[href="?star=yes"]')
  end

  it "generates an href that removes the param when toggling off" do
    render_inline(described_class.new(label: "starred", param: "star", current_params: { "star" => "yes" }))
    expect(page).to have_css('a.filter-chip[href="?"]')
  end

  it "preserves other URL params when toggling on" do
    render_inline(described_class.new(
      label: "connected",
      param: "connected",
      current_params: { "star" => "yes", "page" => "2" }
    ))
    href = page.find("a.filter-chip")["href"]
    expect(href).to start_with("?")
    pairs = href.delete_prefix("?").split("&")
    expect(pairs).to contain_exactly("star=yes", "page=2", "connected=yes")
  end

  it "preserves other URL params when toggling off" do
    render_inline(described_class.new(
      label: "connected",
      param: "connected",
      current_params: { "star" => "yes", "connected" => "yes", "page" => "2" }
    ))
    href = page.find("a.filter-chip")["href"]
    pairs = href.delete_prefix("?").split("&")
    expect(pairs).to contain_exactly("star=yes", "page=2")
  end

  it "supports a custom value" do
    render_inline(described_class.new(label: "size", param: "size", value: "lg", current_params: { "size" => "lg" }))
    expect(page).to have_css("span.md-check-static", text: "[x]")
    expect(page).to have_css('a.filter-chip[href="?"]')
  end

  it "uses the design-system filter-chip class for styling" do
    # The filter-chip CSS rule applies the design-system link color.
    render_inline(described_class.new(label: "starred", param: "star"))
    expect(page).to have_css("a.filter-chip")
  end
end
