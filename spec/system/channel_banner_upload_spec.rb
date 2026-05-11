require "rails_helper"

# Phase 7.5 §11f — Channel banner upload. ONE selective system spec
# (architect rule D — system specs are critical-path only).
#
# The project runs Capybara on `rack_test` (no JS driver — see
# `spec/system/settings/tokens_spec.rb` note). The four client-side
# reject conditions live inside the Stimulus controller and are
# unreachable without a JS-capable driver, so this spec asserts the
# SSR scaffolding the controller needs at boot time:
#
#   - the `banner-upload` controller is mounted on the fieldset,
#   - the four numeric validation thresholds are on the data-* values
#     (min width, min height, aspect ratio, max size),
#   - the drop zone + hidden file input + picker button + error /
#     progress / preview targets are all present,
#   - the spec-info line carries the exact copy the spec demands.
#
# The full reject-condition matrix (wrong type / dimensions / aspect /
# size) is covered by manual test recipe step 3–6 in the parent spec.
# Server-side rejection (D14 authoritative gate, including the YouTube
# 400 imageDimensionsInvalid path) is covered by the request and
# service specs.
RSpec.describe "Channel banner upload form scaffolding", type: :system do
  let(:connection) { create(:youtube_connection) }
  let!(:channel) do
    create(:channel,
           channel_url: "https://www.youtube.com/channel/UCabcabcabcabcabcabcabcA",
           title: "Cached title",
           description: "Cached description",
           youtube_connection: connection)
  end

  before do
    driven_by(:rack_test)
  end

  it "mounts the banner-upload Stimulus controller on the fieldset" do
    visit edit_channel_path(channel)
    fieldset = find('[data-controller~="banner-upload"]')
    expect(fieldset).to be_present
  end

  it "renders the spec-info line with the exact copy" do
    visit edit_channel_path(channel)
    expect(page).to have_content("Banner: 2048x1152 minimum, 16:9 aspect, JPEG/PNG, max 6MB.")
  end

  it "wires the four validation thresholds as data-* values" do
    visit edit_channel_path(channel)
    fieldset = find('[data-controller~="banner-upload"]')
    expect(fieldset["data-banner-upload-min-width-value"]).to eq("2048")
    expect(fieldset["data-banner-upload-min-height-value"]).to eq("1152")
    expect(fieldset["data-banner-upload-aspect-ratio-value"]).to start_with("1.7")
    expect(fieldset["data-banner-upload-max-size-bytes-value"]).to eq("6291456")
  end

  it "renders the hidden file input with banner_image name and JPEG/PNG accept" do
    visit edit_channel_path(channel)
    input = find('input[name="channel[banner_image]"]', visible: :all)
    expect(input["type"]).to eq("file")
    expect(input["accept"]).to eq("image/png,image/jpeg")
    expect(input["data-banner-upload-target"]).to eq("input")
  end

  it "renders the drop zone with the four drag/drop event hooks" do
    visit edit_channel_path(channel)
    drop_zone = find('[data-banner-upload-target="dropZone"]')
    actions = drop_zone["data-action"].to_s
    expect(actions).to include("dragover->banner-upload#onDragOver")
    expect(actions).to include("dragleave->banner-upload#onDragLeave")
    expect(actions).to include("drop->banner-upload#onDrop")
  end

  it "renders the [pick file] picker button wired to openPicker" do
    visit edit_channel_path(channel)
    button = find('[data-banner-upload-target="pickerButton"]')
    expect(button["data-action"]).to include("click->banner-upload#openPicker")
    expect(button.text).to include("pick file")
  end

  it "renders the error / progress / preview targets hidden by default" do
    visit edit_channel_path(channel)
    expect(page).to have_selector('[data-banner-upload-target="errors"]', visible: :hidden)
    expect(page).to have_selector('[data-banner-upload-target="progress"]', visible: :hidden)
    expect(page).to have_selector('[data-banner-upload-target="previewContainer"]', visible: :hidden)
  end

  it "renders all three preview size variants (web / mobile / tv)" do
    visit edit_channel_path(channel)
    expect(page).to have_selector('[data-banner-upload-target="previewWeb"]', visible: :all)
    expect(page).to have_selector('[data-banner-upload-target="previewMobile"]', visible: :all)
    expect(page).to have_selector('[data-banner-upload-target="previewTv"]', visible: :all)
  end

  it "wraps the banner section so the Turbo Stream swap target exists" do
    visit edit_channel_path(channel)
    expect(page).to have_selector("#channel-banner-section")
  end

  it "renders the form with multipart enctype so the picked file actually uploads" do
    visit edit_channel_path(channel)
    form = find("form.edit_channel, form#new_channel, form[action*=\"/channels/\"]")
    expect(form["enctype"]).to eq("multipart/form-data")
  end

  it "happy path — valid banner submit triggers upload + redirect with new banner_url cached" do
    fake_client = instance_double(
      Youtube::Client,
      upload_banner: "https://yt3.googleusercontent.com/abc/banner.jpg"
    )
    allow(Youtube::Client).to receive(:new).and_return(fake_client)

    banner_io = Rack::Test::UploadedFile.new(
      StringIO.new("fake_jpeg_bytes"),
      "image/jpeg",
      original_filename: "banner.jpg"
    )

    page.driver.submit :patch, channel_path(channel), { channel: { banner_image: banner_io } }

    expect(fake_client).to have_received(:upload_banner)
    expect(channel.reload.banner_url).to eq("https://yt3.googleusercontent.com/abc/banner.jpg")
  end
end
