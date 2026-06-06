# frozen_string_literal: true

require "rails_helper"
require_relative "../../../../../support/notification_double"

RSpec.describe Pito::Notifications::Formatter::Templates::Base do
  subject(:base_class) { described_class }

  it "raises NotImplementedError for title on a bare subclass" do
    subclass = Class.new(described_class)
    expect { subclass.new(double("notification")).title }.to raise_error(NotImplementedError)
  end

  it "raises NotImplementedError for body on a bare subclass" do
    subclass = Class.new(described_class)
    expect { subclass.new(double("notification")).body }.to raise_error(NotImplementedError)
  end

  it "raises NotImplementedError for url on a bare subclass" do
    subclass = Class.new(described_class)
    expect { subclass.new(double("notification")).url }.to raise_error(NotImplementedError)
  end

  describe "#payload (private accessor)" do
    let(:notification) do
      NotificationDouble.new(event_payload: { "key" => "val" })
    end

    it "converts event_payload to HashWithIndifferentAccess" do
      # Access via a concrete subclass that exposes payload indirectly
      klass = Class.new(described_class) do
        def title; fetch(:key); end
        def body; ""; end
        def url; nil; end
      end

      expect(klass.new(notification).title).to eq("val")
    end

    it "handles nil event_payload gracefully (returns empty hash)" do
      klass = Class.new(described_class) do
        def title; fetch(:missing, "fallback"); end
        def body; ""; end
        def url; nil; end
      end
      n = NotificationDouble.new(event_payload: nil)
      expect(klass.new(n).title).to eq("fallback")
    end
  end

  describe "join_list (private helper)" do
    let(:klass) do
      Class.new(described_class) do
        def title; join_list(fetch(:items)); end
        def body; ""; end
        def url; nil; end
      end
    end

    it "joins a normal array with commas" do
      n = NotificationDouble.new(event_payload: { "items" => %w[PC Mac] })
      expect(klass.new(n).title).to eq("PC, Mac")
    end

    it "returns the fallback for nil array" do
      n = NotificationDouble.new(event_payload: {})
      expect(klass.new(n).title).to eq("")
    end

    it "returns the fallback for empty array" do
      n = NotificationDouble.new(event_payload: { "items" => [] })
      expect(klass.new(n).title).to eq("")
    end

    it "skips blank entries" do
      n = NotificationDouble.new(event_payload: { "items" => [ "PC", "", nil, "Mac" ] })
      expect(klass.new(n).title).to eq("PC, Mac")
    end
  end
end
