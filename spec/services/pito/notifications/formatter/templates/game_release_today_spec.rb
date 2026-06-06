# frozen_string_literal: true

require "rails_helper"
require_relative "../../../../../support/notification_double"

RSpec.describe Pito::Notifications::Formatter::Templates::GameReleaseToday do
  def notification(payload)
    NotificationDouble.new(
      event_payload: payload,
      id: 1,
      source_calendar_entry_id: nil,
      severity: "info",
      event_type: "game_release_today",
      fires_at: Time.current,
      read_at: nil
    )
  end

  subject(:template) { described_class.new(notification(payload)) }

  context "with full payload" do
    let(:payload) do
      {
        "game_title" => "Hollow Knight",
        "game_id"    => 99,
        "platforms"  => %w[PC Switch],
        "igdb_url"   => "https://igdb.com/games/hollow-knight"
      }
    end

    it "title includes game_title + 'releases today'" do
      expect(template.title).to eq("Hollow Knight releases today")
    end

    it "body names the title, platforms, and igdb link" do
      expect(template.body).to eq(
        "Hollow Knight is out today on PC, Switch. [igdb](https://igdb.com/games/hollow-knight)"
      )
    end

    it "url is /games/<game_id>" do
      expect(template.url).to eq("/games/99")
    end
  end

  context "without igdb_url" do
    let(:payload) { { "game_title" => "Celeste", "game_id" => 7, "platforms" => [ "PC" ] } }

    it "body omits the igdb link" do
      expect(template.body).to eq("Celeste is out today on PC.")
    end
  end

  context "without platforms" do
    let(:payload) { { "game_title" => "Celeste", "game_id" => 7 } }

    it "body falls back to 'tbd'" do
      expect(template.body).to include("tbd")
    end
  end

  context "without game_id" do
    let(:payload) { { "game_title" => "Celeste" } }

    it "url is nil" do
      expect(template.url).to be_nil
    end
  end

  context "with completely empty payload" do
    let(:payload) { {} }

    it "title contains the placeholder" do
      expect(template.title).to include("game title")
    end

    it "url is nil" do
      expect(template.url).to be_nil
    end
  end
end
