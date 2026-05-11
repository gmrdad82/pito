require "rails_helper"

# Phase 11 §01a — Video edit page polish. Chapters sub-section.
RSpec.describe "videos/_edit_chapters.html.erb", type: :view do
  let(:channel) { create(:channel) }

  def render_with(video, chapters)
    assign(:video_chapters, chapters)
    template = <<~ERB
      <%= form_with model: video do |f| %>
        <%= render "videos/edit_chapters", video: video, f: f %>
      <% end %>
    ERB
    render inline: template, locals: { video: video }
  end

  it "renders the [add chapter] button" do
    video = create(:video, channel: channel)
    render_with(video, [])
    expect(rendered).to include("[add chapter]")
  end

  it "renders a nested-form Stimulus controller binding" do
    video = create(:video, channel: channel)
    render_with(video, [])
    expect(rendered).to include('data-controller="nested-form"')
    expect(rendered).to include('data-nested-form-target="rows"')
    expect(rendered).to include('data-nested-form-target="template"')
  end

  it "renders persisted chapters as rows" do
    video = create(:video, channel: channel)
    c1 = create(:video_chapter, video: video, start_seconds: 0, label: "intro")
    c2 = create(:video_chapter, video: video, start_seconds: 120, label: "setup")
    render_with(video, [ c1, c2 ])
    expect(rendered).to include("intro")
    expect(rendered).to include("setup")
    expect(rendered).to match(/name="video\[video_chapters_attributes\]\[0\]\[start_seconds\]"/)
  end

  it "renders the new-row template with __INDEX__ placeholder" do
    video = create(:video, channel: channel)
    render_with(video, [])
    expect(rendered).to include("__INDEX__")
  end

  it "does not include JS confirm tokens" do
    video = create(:video, channel: channel)
    render_with(video, [])
    expect(rendered).not_to include("data-turbo-confirm")
    expect(rendered).not_to match(/window\.confirm/)
  end
end
