# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::ImagePath do
  describe ".call" do
    let(:game) { create(:game) }

    context "when an attachment is present" do
      before do
        game.cover_art.attach(
          io:           StringIO.new("fake-jpeg-data"),
          filename:     "cover.jpg",
          content_type: "image/jpeg"
        )
      end

      it "returns a relative, host-less proxy path for the plain attachment" do
        path = described_class.call(game.cover_art)

        expect(path).to start_with("/rails/active_storage/")
        expect(path).not_to include("http")
      end

      it "returns a relative, host-less proxy path for a named variant" do
        path = described_class.call(game.cover_art, variant: :strip)

        expect(path).to start_with("/rails/active_storage/")
        expect(path).not_to include("http")
      end
    end

    context "when the record has nothing attached" do
      it "returns nil" do
        expect(described_class.call(game.cover_art)).to be_nil
      end
    end

    context "when given nil" do
      it "returns nil" do
        expect(described_class.call(nil)).to be_nil
      end
    end
  end
end
