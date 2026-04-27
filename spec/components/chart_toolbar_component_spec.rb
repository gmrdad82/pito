require "rails_helper"

RSpec.describe ChartToolbarComponent, type: :component do
  it "renders all range options" do
    render_inline(described_class.new(current_range: "30d", base_path: "/"))
    %w[ 7d 30d 90d 1y all ].each do |range|
      expect(page).to have_text(range)
    end
  end

  it "marks active range as bold" do
    render_inline(described_class.new(current_range: "7d", base_path: "/"))
    expect(page).to have_css("span[style*='font-weight: bold']", text: /7d/)
  end

  it "renders inactive ranges as links" do
    render_inline(described_class.new(current_range: "7d", base_path: "/"))
    expect(page).to have_link("[30d]", href: "/?range=30d")
  end

  it "builds correct paths" do
    render_inline(described_class.new(current_range: "30d", base_path: "/dashboard"))
    expect(page).to have_link("[7d]", href: "/dashboard?range=7d")
  end
end
