# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Notifications::Source::PrivateReminder do
  include ActiveSupport::Testing::TimeHelpers

  # The copy sampler is pinned to the FIRST dictionary entry for the whole
  # suite (spec/support/copy.rb), so the rendered line is deterministic. We
  # compute the expected text the same way the source does: render via
  # Pito::Copy, then resolve the inline {singular|plural} token ourselves.
  def expected_line(count)
    Pito::Copy.render("pito.copy.private_reminder", count: count)
               .gsub(/\{(\w+)\|(\w+)\}/) { count == 1 ? Regexp.last_match(1) : Regexp.last_match(2) }
  end

  describe ".report!" do
    context "with a positive count" do
      it "creates a Notification" do
        expect { described_class.report!(3) }.to change(Notification, :count).by(1)
      end

      it "uses level 'warning'" do
        described_class.report!(3)
        expect(Notification.last.level).to eq("warning")
      end

      it "includes the dictionary line with the count and plural word resolved" do
        described_class.report!(3)
        expect(Notification.last.message).to include(expected_line(3))
      end

      context "when count is 1 (singular word choice)" do
        it "resolves the singular half of the {singular|plural} token" do
          described_class.report!(1)
          expect(Notification.last.message).to include(expected_line(1))
        end
      end
    end

    context "with a zero count" do
      it "creates nothing" do
        expect { described_class.report!(0) }.not_to change(Notification, :count)
      end

      it "returns nil" do
        expect(described_class.report!(0)).to be_nil
      end
    end

    context "same-day dedupe" do
      it "creates nothing on a second call the same day" do
        described_class.report!(3)
        expect { described_class.report!(5) }.not_to change(Notification, :count)
      end

      it "returns nil on the deduped call" do
        described_class.report!(3)
        expect(described_class.report!(5)).to be_nil
      end
    end

    context "next-day call" do
      it "creates again once the calendar day rolls over" do
        described_class.report!(3)

        travel_to(1.day.from_now) do
          expect { described_class.report!(4) }.to change(Notification, :count).by(1)
        end
      end
    end
  end
end
