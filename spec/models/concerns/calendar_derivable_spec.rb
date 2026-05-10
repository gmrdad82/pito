require "rails_helper"

# Phase 15 §1 — `CalendarDerivable` is a thin mixin that delegates to
# `Calendar::Derivation`. Per-host integration is covered in
# `spec/services/calendar/derivation_spec.rb` (Video/Channel/Game) and
# `spec/models/game_calendar_derivation_spec.rb`. This spec pins the
# concern's own contract — the dispatch logic in `sync_calendar_entry`
# and the two pass-through helpers.
RSpec.describe CalendarDerivable do
  let(:host_class) do
    Class.new do
      include CalendarDerivable

      attr_accessor :stub_attrs

      def calendar_entry_type
        :video_published
      end

      def calendar_entry_attributes
        @stub_attrs
      end

      def calendar_entry_source_ref
        { "video_id" => 1 }
      end
    end
  end

  let(:host) { host_class.new }

  describe "#derive_calendar_entry!" do
    it "delegates to Calendar::Derivation.sync!" do
      expect(Calendar::Derivation).to receive(:sync!).with(host)
      host.derive_calendar_entry!
    end
  end

  describe "#revoke_calendar_entry!" do
    it "delegates to Calendar::Derivation.revoke!" do
      expect(Calendar::Derivation).to receive(:revoke!).with(host)
      host.revoke_calendar_entry!
    end
  end

  describe "#sync_calendar_entry" do
    context "when calendar_entry_attributes returns nil" do
      it "calls revoke_all_for_host! (not sync!)" do
        host.stub_attrs = nil
        expect(Calendar::Derivation).to receive(:revoke_all_for_host!).with(host)
        expect(Calendar::Derivation).not_to receive(:sync!)
        host.sync_calendar_entry
      end
    end

    context "when calendar_entry_attributes returns a hash" do
      it "calls sync! (not revoke_all_for_host!)" do
        host.stub_attrs = { title: "x", starts_at: Time.current, all_day: false }
        expect(Calendar::Derivation).to receive(:sync!).with(host)
        expect(Calendar::Derivation).not_to receive(:revoke_all_for_host!)
        host.sync_calendar_entry
      end
    end

    context "edge — empty hash counts as 'present' (not nil)" do
      it "still routes to sync! (Derivation handles validation)" do
        host.stub_attrs = {}
        expect(Calendar::Derivation).to receive(:sync!).with(host)
        host.sync_calendar_entry
      end
    end

    context "flaw — host with the mixin but no calendar_entry_attributes method" do
      it "raises NameError (mixin requires the host contract)" do
        bare_class = Class.new { include CalendarDerivable }
        bare = bare_class.new
        # Ruby's bare-method-call lookup raises a plain NameError when
        # neither a local variable nor a method exists; that's the
        # parent class of NoMethodError. Either way the contract gap
        # surfaces immediately rather than corrupting state.
        expect { bare.sync_calendar_entry }.to raise_error(NameError)
      end
    end
  end

  describe "real-world host integration" do
    # Anchor the abstract contract to the three concrete hosts the
    # mixin documents. Channel is the simplest derive-on-create flow.
    it "persists a CalendarEntry when a Channel is created" do
      ch = create(:channel)
      ce = CalendarEntry.where(channel_id: ch.id, entry_type: :channel_published).first
      expect(ce).to be_present
    end

    it "persists a CalendarEntry when a Video transitions to public" do
      ch = create(:channel)
      v = create(:video, channel: ch)
      v.update!(privacy_status: :public, published_at: 1.day.ago, title: "hi", category_id: "10")
      ce = CalendarEntry.where(video_id: v.id, entry_type: :video_published).first
      expect(ce).to be_present
    end
  end
end
