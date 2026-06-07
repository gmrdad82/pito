# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Sidebar::Conversations::Component do
  # A simple struct that mimics what Conversation.by_recent_activity returns.
  ConvStub = Struct.new(:display_name, :uuid, :last_activity_at, keyword_init: true)

  let(:recent_conv) do
    ConvStub.new(
      display_name:     "My Chat",
      uuid:             "aaaaaaaa-0000-0000-0000-000000000001",
      last_activity_at: 2.hours.ago
    )
  end

  let(:older_conv) do
    ConvStub.new(
      display_name:     "Old Chat",
      uuid:             "bbbbbbbb-0000-0000-0000-000000000002",
      last_activity_at: 10.days.ago
    )
  end

  def groups(recent: [], older: [])
    { recent: recent, older: older }
  end

  describe "basic rendering" do
    it "renders a row for each conversation" do
      node = render_inline(described_class.new(groups: groups(recent: [ recent_conv ])))
      expect(node.css(".pito-conversation-row").size).to eq(1)
    end

    it "shows display_name in the row" do
      node = render_inline(described_class.new(groups: groups(recent: [ recent_conv ])))
      expect(node.to_html).to include("My Chat")
    end

    it "includes a formatted timestamp in the row" do
      node = render_inline(described_class.new(groups: groups(recent: [ recent_conv ])))
      # 2 hours ago — CompactTimeAgo renders "~2h ago"
      expect(node.to_html).to match(/~\d+h ago/)
    end
  end

  describe "data attributes" do
    it "sets data-conversation-uuid on every row" do
      node = render_inline(described_class.new(groups: groups(recent: [ recent_conv ])))
      uuids = node.css(".pito-conversation-row").map { |el| el["data-conversation-uuid"] }
      expect(uuids).to include("aaaaaaaa-0000-0000-0000-000000000001")
    end
  end

  describe "current_uuid marking" do
    it "adds is-current class to the matching row" do
      node = render_inline(
        described_class.new(
          groups:       groups(recent: [ recent_conv ]),
          current_uuid: recent_conv.uuid
        )
      )
      current_rows = node.css(".pito-conversation-row.is-current")
      expect(current_rows.size).to eq(1)
      expect(current_rows.first["data-conversation-uuid"]).to eq(recent_conv.uuid)
    end

    it "does not add is-current when no current_uuid is given" do
      node = render_inline(described_class.new(groups: groups(recent: [ recent_conv ])))
      expect(node.css(".pito-conversation-row.is-current")).to be_empty
    end

    it "does not add is-current to non-matching rows" do
      node = render_inline(
        described_class.new(
          groups:       groups(recent: [ recent_conv, older_conv ]),
          current_uuid: recent_conv.uuid
        )
      )
      non_current = node.css(".pito-conversation-row:not(.is-current)")
      expect(non_current.map { |el| el["data-conversation-uuid"] }).to include(older_conv.uuid)
    end

    it "renders the cyan current marker on the current row" do
      node = render_inline(
        described_class.new(
          groups:       groups(recent: [ recent_conv ]),
          current_uuid: recent_conv.uuid
        )
      )
      current_row = node.css(".pito-conversation-row.is-current").first
      # The marker is rendered in a text-cyan span starting with "<- "
      marker_span = current_row.css("span.text-cyan").first
      expect(marker_span).not_to be_nil
      expect(marker_span.text).to start_with("<- ")
    end

    it "does not render the cyan marker on non-current rows" do
      node = render_inline(
        described_class.new(
          groups:       groups(recent: [ recent_conv, older_conv ]),
          current_uuid: recent_conv.uuid
        )
      )
      non_current_row = node.css(".pito-conversation-row:not(.is-current)").first
      expect(non_current_row.css("span.text-cyan")).to be_empty
    end

    it "renders timestamp on non-current rows (not the marker)" do
      node = render_inline(
        described_class.new(
          groups:       groups(recent: [ recent_conv, older_conv ]),
          current_uuid: recent_conv.uuid
        )
      )
      non_current_row = node.css(".pito-conversation-row:not(.is-current)").first
      expect(non_current_row.css("span.text-fg-dim").first).not_to be_nil
    end
  end

  describe "older section / hairline divider" do
    it "does not render a hairline when there are no older conversations" do
      node = render_inline(described_class.new(groups: groups(recent: [ recent_conv ])))
      expect(node.css("hr")).to be_empty
    end

    it "renders a hairline when there are older conversations" do
      node = render_inline(
        described_class.new(groups: groups(recent: [ recent_conv ], older: [ older_conv ]))
      )
      expect(node.css("hr")).not_to be_empty
    end

    it "renders rows for older conversations" do
      node = render_inline(
        described_class.new(groups: groups(recent: [ recent_conv ], older: [ older_conv ]))
      )
      expect(node.css(".pito-conversation-row").size).to eq(2)
      expect(node.to_html).to include("Old Chat")
    end

    it "shows compact relative timestamp for older conversations" do
      node = render_inline(
        described_class.new(groups: groups(recent: [], older: [ older_conv ]))
      )
      # 10.days.ago → CompactTimeAgo renders "~10d ago"
      expect(node.to_html).to match(/~\d+d ago/)
    end
  end

  describe "Recent section label" do
    it "renders the Recent section label" do
      node = render_inline(described_class.new(groups: groups(recent: [ recent_conv ])))
      expect(node.to_html).to include("Recent")
    end
  end

  describe "empty state" do
    it "renders nothing when both buckets are empty" do
      node = render_inline(described_class.new(groups: groups))
      expect(node.css(".pito-conversation-row")).to be_empty
    end
  end

  describe "multiple rows keep uuid data attributes" do
    it "each row carries its own uuid" do
      node = render_inline(
        described_class.new(groups: groups(recent: [ recent_conv, older_conv ]))
      )
      uuids = node.css(".pito-conversation-row").map { |el| el["data-conversation-uuid"] }
      expect(uuids).to contain_exactly(recent_conv.uuid, older_conv.uuid)
    end
  end
end
