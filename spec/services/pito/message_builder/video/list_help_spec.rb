# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::MessageBuilder::Video::ListHelp do
  describe ".call" do
    subject(:result) { described_class.call }

    it "returns an html payload" do
      expect(result).to be_a(Hash)
      expect(result["html"]).to be(true)
      expect(result["body"]).to be_a(String)
    end

    it "body is wrapped in .pito-help-block" do
      expect(result["body"]).to include('class="pito-help-block"')
    end

    it "body includes 'Usage:'" do
      expect(result["body"]).to include("Usage:")
    end

    it "body includes the list vids usage line" do
      expect(result["body"]).to include("list vids")
    end

    it "body includes Options section" do
      expect(result["body"]).to include("Options:")
    end

    it "body includes Columns section" do
      expect(result["body"]).to include("Columns:")
    end

    it "body includes the channel column token" do
      expect(result["body"]).to include("channel")
    end

    it "body includes the visibility column token" do
      expect(result["body"]).to include("visibility")
    end

    it "body includes the game column token" do
      expect(result["body"]).to include("game")
    end

    it "body includes the duration column token" do
      expect(result["body"]).to include("duration")
    end

    it "body includes the views column token" do
      expect(result["body"]).to include("views")
    end

    it "body includes the likes column token" do
      expect(result["body"]).to include("likes")
    end

    it "body includes the comms column token" do
      expect(result["body"]).to include("comms")
    end

    it "body includes the with option" do
      expect(result["body"]).to include("with &lt;columns&gt;")
    end

    it "body includes the sorted by option" do
      expect(result["body"]).to include("sorted by &lt;column&gt;")
    end

    it "body includes --help option" do
      expect(result["body"]).to include("--help")
    end

    it "body includes column descriptions" do
      expect(result["body"]).to include("Channel @handle")
      expect(result["body"]).to include("Status")
      expect(result["body"]).to include("View count")
      expect(result["body"]).to include("Like count")
    end
  end
end
