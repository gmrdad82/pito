# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::FollowUp::Registry, type: :service do
  # Use a fresh isolated registry for each example so these tests do not
  # pollute the real registry (which real handlers register into at load time).
  around do |example|
    saved = described_class.all
    described_class.reset!
    example.run
    described_class.reset!
    # Re-register original handlers so later specs still work.
    saved.each_value { |klass| described_class.register(klass) }
  end

  let(:mutate_handler_class) do
    Class.new(Pito::FollowUp::Handler) do
      target "spec_mutate"
      mode   :mutate
      def call(event:, rest:, conversation:)
        Pito::FollowUp::Result::Mutation.new(kind: :system, payload: {})
      end
    end
  end

  let(:append_handler_class) do
    Class.new(Pito::FollowUp::Handler) do
      target "spec_append"
      mode   :append
      def call(event:, rest:, conversation:)
        Pito::FollowUp::Result::Append.new(events: [ { kind: :system, payload: { text: "hi" } } ])
      end
    end
  end

  before do
    described_class.register(mutate_handler_class)
    described_class.register(append_handler_class)
  end

  describe ".for" do
    it "returns the handler class for a registered target" do
      expect(described_class.for("spec_mutate")).to eq(mutate_handler_class)
    end

    it "returns nil for an unknown target" do
      expect(described_class.for("nonexistent")).to be_nil
    end
  end

  describe ".mode_for" do
    it "returns :mutate for a mutate handler" do
      expect(described_class.mode_for("spec_mutate")).to eq(:mutate)
    end

    it "returns :append for an append handler" do
      expect(described_class.mode_for("spec_append")).to eq(:append)
    end

    it "returns nil for an unknown target" do
      expect(described_class.mode_for("nonexistent")).to be_nil
    end
  end

  describe ".all" do
    it "includes all registered handlers" do
      expect(described_class.all.keys).to include("spec_mutate", "spec_append")
    end

    it "returns a dup (mutation does not affect registry)" do
      snapshot = described_class.all
      snapshot["spec_mutate"] = nil
      expect(described_class.for("spec_mutate")).to eq(mutate_handler_class)
    end
  end
end

RSpec.describe Pito::FollowUp::Handler, type: :service do
  describe "mode validation" do
    it "raises ArgumentError for an invalid mode" do
      expect {
        Class.new(Pito::FollowUp::Handler) { self.mode(:invalid) }
      }.to raise_error(ArgumentError, /mode must be/)
    end
  end

  describe "parse_rest helper" do
    let(:handler) { Class.new(Pito::FollowUp::Handler).new }

    it "splits into action and args" do
      action, args = handler.send(:parse_rest, "preview tokyo-night")
      expect(action).to eq("preview")
      expect(args).to eq("tokyo-night")
    end

    it "returns empty args when only action is present" do
      action, args = handler.send(:parse_rest, "confirm")
      expect(action).to eq("confirm")
      expect(args).to eq("")
    end

    it "downcases the action" do
      action, _args = handler.send(:parse_rest, "APPLY Something")
      expect(action).to eq("apply")
    end
  end

  describe "#call default" do
    it "raises NotImplementedError on the base class" do
      expect {
        Pito::FollowUp::Handler.new.call(event: nil, rest: "", conversation: nil)
      }.to raise_error(NotImplementedError)
    end
  end
end

RSpec.describe Pito::FollowUp::Result, type: :service do
  describe "Mutation" do
    it "is a Data struct with kind and payload" do
      m = Pito::FollowUp::Result::Mutation.new(kind: :system, payload: { text: "hi" })
      expect(m.kind).to eq(:system)
      expect(m.payload).to eq({ text: "hi" })
    end
  end

  describe "Append" do
    it "is a Data struct with events array" do
      a = Pito::FollowUp::Result::Append.new(
        events: [ { kind: :system, payload: { text: "ok" } } ]
      )
      expect(a.events.first[:kind]).to eq(:system)
    end
  end

  describe "Error" do
    it "is a Data struct with message_key and message_args" do
      e = Pito::FollowUp::Result::Error.new(
        message_key: "pito.errors.foo",
        message_args: { name: "bar" }
      )
      expect(e.message_key).to eq("pito.errors.foo")
      expect(e.message_args).to eq({ name: "bar" })
    end
  end
end
