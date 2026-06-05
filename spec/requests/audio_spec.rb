# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Audio integration", type: :request do
  it "mounts the audio controller on the body" do
    get root_path
    expect(response.body).to include('data-controller="pito--audio"')
  end

  it "serves send.mp3 as a static asset" do
    get "/sounds/send.mp3"
    expect(response).to have_http_status(:ok)
    expect(response.content_type).to eq("audio/mpeg")
  end

  it "serves receive.mp3 as a static asset" do
    get "/sounds/receive.mp3"
    expect(response).to have_http_status(:ok)
    expect(response.content_type).to eq("audio/mpeg")
  end
end
