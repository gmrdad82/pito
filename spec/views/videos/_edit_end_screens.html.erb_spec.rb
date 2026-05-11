require "rails_helper"

# Phase 11 §01a — Video edit page polish. End-screens sub-section.
RSpec.describe "videos/_edit_end_screens.html.erb", type: :view do
  let(:channel) { create(:channel) }

  def render_with(video, end_screens)
    assign(:video_end_screens, end_screens)
    template = <<~ERB
      <%= form_with model: video do |f| %>
        <%= render "videos/edit_end_screens", video: video, f: f %>
      <% end %>
    ERB
    render inline: template, locals: { video: video }
  end

  it "renders the [add end screen] button" do
    video = create(:video, channel: channel)
    render_with(video, [])
    expect(rendered).to include("[add end screen]")
  end

  it "renders a nested-form Stimulus controller binding" do
    video = create(:video, channel: channel)
    render_with(video, [])
    expect(rendered).to include('data-controller="nested-form"')
  end

  it "renders persisted end-screens as rows" do
    video = create(:video, channel: channel)
    es = create(:video_end_screen,
                video: video,
                kind: :related_video,
                target_id: "yt_abc",
                target_label: "watch")
    render_with(video, [ es ])
    expect(rendered).to include("yt_abc")
    expect(rendered).to match(/name="video\[video_end_screens_attributes\]\[0\]\[kind\]"/)
  end

  it "renders the four kind options in the select" do
    video = create(:video, channel: channel)
    render_with(video, [])
    expect(rendered).to include('value="related_video"')
    expect(rendered).to include('value="related_channel"')
    expect(rendered).to include('value="related_playlist"')
    expect(rendered).to include('value="none"')
  end

  it "does not include JS confirm tokens" do
    video = create(:video, channel: channel)
    render_with(video, [])
    expect(rendered).not_to include("data-turbo-confirm")
    expect(rendered).not_to match(/window\.confirm/)
  end
end
