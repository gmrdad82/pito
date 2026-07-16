# frozen_string_literal: true

require "rails_helper"

RSpec.describe Notification, type: :model do
  describe "validations" do
    it "is valid with a message" do
      expect(build(:notification)).to be_valid
    end

    it "is invalid without a message" do
      expect(build(:notification, message: nil)).not_to be_valid
    end

    it "is invalid with a blank message" do
      expect(build(:notification, message: "")).not_to be_valid
    end

    it "defaults level to info" do
      expect(create(:notification).level).to eq("info")
    end

    it "accepts the known levels" do
      Notification::LEVELS.each { |lvl| expect(build(:notification, level: lvl)).to be_valid }
    end

    it "accepts level 'shiny'" do
      expect(build(:notification, level: "shiny")).to be_valid
    end

    it "rejects an unknown level" do
      expect(build(:notification, level: "critical")).not_to be_valid
    end
  end

  describe "scopes" do
    let!(:unread1) { create(:notification, created_at: 1.hour.ago) }
    let!(:unread2) { create(:notification, created_at: 2.hours.ago) }
    let!(:read_one) { create(:notification, :read, created_at: 3.hours.ago) }

    describe ".unread" do
      it "returns only notifications with read_at nil" do
        expect(Notification.unread).to contain_exactly(unread1, unread2)
      end

      it "excludes read notifications" do
        expect(Notification.unread).not_to include(read_one)
      end
    end

    describe ".recent" do
      it "orders newest first" do
        ids = Notification.recent.pluck(:id)
        expect(ids).to eq([ unread1.id, unread2.id, read_one.id ])
      end
    end

    describe ".panel_ordered" do
      it "returns unread notifications before read ones" do
        ids = Notification.panel_ordered.pluck(:id)
        read_index   = ids.index(read_one.id)
        unread_indexes = [ ids.index(unread1.id), ids.index(unread2.id) ]
        expect(unread_indexes).to all(be < read_index)
      end

      it "orders unread rows newest-first within the unread group" do
        ids = Notification.panel_ordered.pluck(:id)
        # unread1 (1 hour ago) is newer than unread2 (2 hours ago)
        expect(ids.index(unread1.id)).to be < ids.index(unread2.id)
      end

      it "places all read rows after all unread rows even with varied timestamps" do
        extra_read = create(:notification, :read, created_at: 30.minutes.ago)
        ids = Notification.panel_ordered.pluck(:id)
        unread_ids = [ unread1.id, unread2.id ]
        read_ids   = [ read_one.id, extra_read.id ]

        last_unread_pos = unread_ids.map { ids.index(_1) }.max
        first_read_pos  = read_ids.map { ids.index(_1) }.min
        expect(last_unread_pos).to be < first_read_pos
      end

      it "orders read rows newest-first within the read group" do
        older_read  = create(:notification, :read, created_at: 6.hours.ago)
        newer_read  = create(:notification, :read, created_at: 30.minutes.ago)
        ids = Notification.panel_ordered.pluck(:id)
        expect(ids.index(newer_read.id)).to be < ids.index(older_read.id)
      end
    end
  end

  describe "keyset pagination (.panel_after / .panel_page / .cursor_for)" do
    it "PAGE_SIZE is 50" do
      expect(Notification::PAGE_SIZE).to eq(50)
    end

    it "panel_ordered carries an id tiebreak so same-created_at rows are stable" do
      t = 2.hours.ago
      a = create(:notification, created_at: t)
      b = create(:notification, created_at: t)
      c = create(:notification, created_at: t)
      # same timestamp → ordered by id DESC (newest id first)
      ids = Notification.panel_ordered.where(created_at: t).pluck(:id)
      expect(ids).to eq([ c.id, b.id, a.id ])
    end

    describe ".panel_page" do
      it "returns at most PAGE_SIZE rows and a next cursor when more exist" do
        create_list(:notification, Notification::PAGE_SIZE + 3)
        rows, cursor = Notification.panel_page
        expect(rows.size).to eq(Notification::PAGE_SIZE)
        expect(cursor).to be_present
      end

      it "returns a nil cursor on the last page" do
        create_list(:notification, 3)
        rows, cursor = Notification.panel_page
        expect(rows.size).to eq(3)
        expect(cursor).to be_nil
      end

      it "walks every row exactly once, in panel_ordered order, via the cursor" do
        # mix unread + read so the walk crosses the read-bucket boundary
        create_list(:notification, Notification::PAGE_SIZE + 2)
        create_list(:notification, 4, :read)

        walked = []
        cursor = nil
        loop do
          rows, cursor = Notification.panel_page(after: cursor)
          walked.concat(rows.map(&:id))
          break if cursor.nil?
        end

        expect(walked).to eq(Notification.panel_ordered.pluck(:id))
        expect(walked.tally.select { |_, n| n > 1 }).to be_empty
      end

      it "falls back to the first page for a malformed cursor" do
        create_list(:notification, 2)
        rows, = Notification.panel_page(after: "@@@garbage@@@")
        expect(rows.map(&:id)).to eq(Notification.panel_ordered.first(2).map(&:id))
      end
    end

    describe ".cursor_for" do
      it "encodes a row into a token that panel_page can resume from" do
        create_list(:notification, 5)
        first_three = Notification.panel_ordered.limit(3).to_a
        cursor = Notification.cursor_for(first_three.last)
        rows, = Notification.panel_page(after: cursor)
        expect(rows.map(&:id) & first_three.map(&:id)).to be_empty
      end
    end
  end

  describe "predicates" do
    it "#read? returns false when read_at is nil" do
      n = build(:notification)
      expect(n.read?).to be false
    end

    it "#read? returns true when read_at is set" do
      n = build(:notification, :read)
      expect(n.read?).to be true
    end

    it "#unread? is the inverse of read?" do
      unread = build(:notification)
      read   = build(:notification, :read)
      expect(unread.unread?).to be true
      expect(read.unread?).to be false
    end
  end

  describe "#mark_read!" do
    it "sets read_at to the current time" do
      n = create(:notification)
      before = Time.current
      n.mark_read!
      expect(n.reload.read_at).to be >= before
    end

    it "persists the change" do
      n = create(:notification)
      n.mark_read!
      expect(n.reload.read?).to be true
    end

    it "is idempotent (calling twice does not raise)" do
      n = create(:notification)
      n.mark_read!
      expect { n.mark_read! }.not_to raise_error
    end
  end

  describe "webhook delivery callback" do
    it "enqueues NotificationWebhookDeliverJob after create commit" do
      expect {
        create(:notification)
      }.to have_enqueued_job(NotificationWebhookDeliverJob)
        .with(a_kind_of(Integer))
    end

    it "passes the persisted record id to the job" do
      notification = nil
      expect {
        notification = create(:notification)
      }.to have_enqueued_job(NotificationWebhookDeliverJob)
        .with { |id| expect(id).to eq(notification.id) }
    end

    it "does not enqueue NotificationWebhookDeliverJob when skip_webhook is true" do
      notification = nil
      expect {
        notification = create(:notification, skip_webhook: true)
      }.not_to have_enqueued_job(NotificationWebhookDeliverJob)
      expect(notification).to be_persisted
    end
  end

  describe "#mark_unread!" do
    it "clears read_at" do
      n = create(:notification, :read)
      n.mark_unread!
      expect(n.reload.read_at).to be_nil
    end

    it "makes #read? false" do
      n = create(:notification, :read)
      n.mark_unread!
      expect(n.reload.read?).to be false
    end

    it "is idempotent (calling twice does not raise)" do
      n = create(:notification)
      n.mark_unread!
      expect { n.mark_unread! }.not_to raise_error
    end
  end

  describe "live mini-status broadcast on create" do
    it "broadcasts a pito-mini-status replace to pito:global so open windows update without a refresh" do
      expect { create(:notification) }
        .to have_broadcasted_to("pito:global").with { |msg|
          html = msg.is_a?(Hash) ? msg.values.join : msg.to_s
          expect(html).to include("pito-mini-status")
        }
    end

    it "still broadcasts the pito-mini-status replace when skip_webhook is true" do
      expect { create(:notification, skip_webhook: true) }
        .to have_broadcasted_to("pito:global").with { |msg|
          html = msg.is_a?(Hash) ? msg.values.join : msg.to_s
          expect(html).to include("pito-mini-status")
        }
    end
  end
end
