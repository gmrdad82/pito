# frozen_string_literal: true

require "rails_helper"

RSpec.describe PurgeUnnamedConversationsJob do
  before { allow(Pito::Stream::Broadcaster).to receive(:broadcast_global_conversation_row) }

  # An UNNAMED conversation made "old" via a 40-day-old event.
  def old_unnamed
    c = create(:conversation)
    t = create(:turn, conversation: c)
    create(:event, conversation: c, turn: t, created_at: 40.days.ago)
    c
  end

  it "enqueues a deletion for each old unnamed conversation" do
    a = old_unnamed
    b = old_unnamed
    expect { described_class.perform_now }
      .to have_enqueued_job(DeleteConversationJob).with(a.id)
      .and have_enqueued_job(DeleteConversationJob).with(b.id)
  end

  it "NEVER enqueues a deletion for a named conversation, even when old" do
    named = create(:conversation, :named)
    t = create(:turn, conversation: named)
    create(:event, conversation: named, turn: t, created_at: 40.days.ago)
    expect { described_class.perform_now }.not_to have_enqueued_job(DeleteConversationJob)
  end

  it "leaves recently-active unnamed conversations alone" do
    create(:conversation) # no events → last_activity = created_at (now)
    expect { described_class.perform_now }.not_to have_enqueued_job(DeleteConversationJob)
  end

  it "marks each purged conversation as deleting (in-flight)" do
    c = old_unnamed
    described_class.perform_now
    expect(c.reload.deleting_at).to be_present
  end

  it "is idempotent — re-running enqueues no second deletion for an in-flight conversation" do
    old_unnamed
    described_class.perform_now
    expect { described_class.perform_now }.not_to have_enqueued_job(DeleteConversationJob)
  end
end
