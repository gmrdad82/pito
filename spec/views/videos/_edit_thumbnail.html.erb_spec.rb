require "rails_helper"

# Phase 11 §01a — Video edit page polish. Thumbnail sub-section.
RSpec.describe "videos/_edit_thumbnail.html.erb", type: :view do
  let(:channel) { create(:channel) }

  def render_with(video)
    template = <<~ERB
      <%= form_with model: video, multipart: true do |f| %>
        <%= render "videos/edit_thumbnail", video: video, f: f %>
      <% end %>
    ERB
    render inline: template, locals: { video: video }
  end

  it "renders a file_field for video[thumbnail] when none is attached" do
    video = create(:video, channel: channel)
    render_with(video)
    expect(rendered).to include('name="video[thumbnail]"')
    expect(rendered).to include("no thumbnail attached yet")
  end

  it "renders the preview image tag when a thumbnail is attached" do
    video = create(:video, :with_thumbnail, channel: channel)
    render_with(video)
    expect(rendered).to include("video thumbnail preview")
    expect(rendered).to match(/img\b/)
  end

  it "displays the file name when attached" do
    video = create(:video, :with_thumbnail, channel: channel)
    render_with(video)
    expect(rendered).to include("thumb.png")
  end

  it "advertises the PNG/JPEG and 2mb limits" do
    video = create(:video, channel: channel)
    render_with(video)
    expect(rendered).to include("png or jpeg")
    expect(rendered).to include("2 mb")
  end

  it "does not include JS confirm tokens" do
    video = create(:video, channel: channel)
    render_with(video)
    expect(rendered).not_to include("data-turbo-confirm")
    expect(rendered).not_to match(/window\.confirm/)
  end
end
