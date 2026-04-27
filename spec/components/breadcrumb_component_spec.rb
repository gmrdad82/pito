require "rails_helper"

RSpec.describe BreadcrumbComponent, type: :component do
  it "renders a single crumb as active" do
    render_inline(described_class.new(crumbs: [ "home" ]))
    expect(page).to have_css("span", text: "[ home ]")
    expect(page).to have_no_css("a")
  end

  it "renders multiple crumbs with separator" do
    render_inline(described_class.new(crumbs: [ [ "channels", "/channels" ], "delete" ]))
    expect(page).to have_link("[ channels ]", href: "/channels")
    expect(page).to have_css("span", text: "[ delete ]")
    expect(page).to have_css("span.text-muted", text: "/")
  end

  it "truncates long non-last segment labels" do
    long_label = "a" * 50
    render_inline(described_class.new(crumbs: [ [ long_label, "/x" ], "end" ]))
    expect(page).to have_no_text(long_label)
  end

  it "preserves longer last segment" do
    long_label = "a" * 50
    render_inline(described_class.new(crumbs: [ [ "start", "/x" ], long_label ]))
    expect(page).to have_text(long_label)
  end

  it "renders three segments with two separators" do
    crumbs = [ [ "channels", "/channels" ], [ "my channel", "/channels/1" ], "videos" ]
    render_inline(described_class.new(crumbs: crumbs))
    separators = page.all("span.text-muted").select { |s| s.text.include?("/") }
    expect(separators.size).to eq(2)
  end
end
