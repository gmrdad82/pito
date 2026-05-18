require "rails_helper"

RSpec.describe NotificationFormatter::Templates::GameReleaseToday do
  let(:payload) do
    {
      "game_id"      => 99,
      "game_title"   => "Stardew Valley 2",
      "release_date" => "2026-05-10",
      "igdb_url"     => "https://igdb.com/games/sv2",
      "platforms"    => %w[Windows]
    }
  end
  let(:notification) do
    build_stubbed(:notification, :game_release_today, with_calendar_entry: false, dedup_key: "grt-base", event_payload: payload)
  end
  let(:template) { described_class.new(notification) }

  describe "#title" do
    it "is `<game_title> releases today`" do
      expect(template.title).to eq("Stardew Valley 2 releases today")
    end
  end

  describe "#body" do
    it "is `<game_title> is out today on <platforms>.`" do
      expect(template.body).to include("Stardew Valley 2 is out today on Windows.")
    end

    it "appends the IGDB link when present" do
      expect(template.body).to include("[igdb](https://igdb.com/games/sv2)")
    end

    it "omits the IGDB link when nil" do
      n = build_stubbed(:notification, :game_release_today, with_calendar_entry: false, dedup_key: "grt1",
                 event_payload: payload.merge("igdb_url" => nil))
      expect(described_class.new(n).body).not_to include("igdb")
    end
  end

  describe "#url" do
    it "is /games/<id>" do
      expect(template.url).to eq("/games/99")
    end
  end

  it "is graceful with empty event_payload" do
    n = build(:notification, :game_release_today, event_payload: {})
    n.save!
    t = described_class.new(n)
    expect { t.title }.not_to raise_error
    expect { t.body }.not_to raise_error
    expect { t.url }.not_to raise_error
  end
end
