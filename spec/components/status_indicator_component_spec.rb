require "rails_helper"

RSpec.describe StatusIndicatorComponent, type: :component do
  it "renders up indicator" do
    render_inline(described_class.new(kind: :up, text: "25% ▲"))
    expect(page).to have_css("span.indicator-up", text: "25% ▲")
  end

  it "renders down indicator" do
    render_inline(described_class.new(kind: :down, text: "10% ▼"))
    expect(page).to have_css("span.indicator-down", text: "10% ▼")
  end

  it "renders flat indicator" do
    render_inline(described_class.new(kind: :flat, text: "— flat"))
    expect(page).to have_css("span.indicator-flat", text: "— flat")
  end

  it "renders loading indicator" do
    render_inline(described_class.new(kind: :loading, text: ""))
    expect(page).to have_css("span.dot-loader")
  end

  it "renders done indicator" do
    render_inline(described_class.new(kind: :done, text: "done"))
    expect(page).to have_css("span.dot-done", text: "done")
  end

  it "renders fail indicator" do
    render_inline(described_class.new(kind: :fail, text: "fail"))
    expect(page).to have_css("span.dot-fail", text: "fail")
  end

  it "includes sort_value data attribute when provided" do
    render_inline(described_class.new(kind: :up, text: "25% ▲", sort_value: 25))
    expect(page).to have_css('span[data-sort-value="25"]')
  end

  it "omits sort_value data attribute when not provided" do
    render_inline(described_class.new(kind: :up, text: "25% ▲"))
    expect(page).to have_no_css("span[data-sort-value]")
  end

  it "applies loader delay style" do
    render_inline(described_class.new(kind: :loading, text: "", loader_delay: "-0.3s"))
    expect(page).to have_css('span[style*="--loader-delay: -0.3s"]')
  end
end
