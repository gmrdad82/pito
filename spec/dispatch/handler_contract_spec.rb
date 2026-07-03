# frozen_string_literal: true

require "rails_helper"

# The uniform dispatch contract (plan-0.9.5 T8.10) — the add-a-verb foundation.
#
# EVERY chat verb's `chat.dispatch` class in config/pito/verbs.yml must answer
# the single contract the Router invokes: `call(kwargs:, context:) -> Result`.
# When this holds, a new verb needs only (1) a config entry naming its dispatch
# class and (2) a Pito::Chat::Handler subclass — ZERO Router edits (that proof
# is T8.12b; this spec pins the property it relies on).
RSpec.describe "chat verb dispatch contract", type: :dispatch do
  Pito::Dispatch::Config.reload!
  CHAT_DISPATCH_ROWS = Pito::Dispatch::Config.data[:verbs].filter_map do |verb, body|
    dispatch = body.dig(:chat, :dispatch)
    { verb:, class_string: dispatch } if dispatch.is_a?(String)
  end.freeze

  it "every implemented chat verb declares a dispatch class" do
    expect(CHAT_DISPATCH_ROWS).not_to be_empty
  end

  describe "each chat.dispatch class answers call(kwargs:, context:)" do
    CHAT_DISPATCH_ROWS.each do |row|
      describe "verbs.#{row[:verb]}.chat.dispatch → Pito::#{row[:class_string]}" do
        let(:klass) { "Pito::#{row[:class_string]}".constantize }

        it "constantizes to a Class" do
          expect(klass).to be_a(Class)
        end

        it "responds to a class-level .call" do
          expect(klass).to respond_to(:call)
        end

        it "declares kwargs: and context: as required keywords" do
          params = klass.method(:call).parameters
          expect(params).to include([ :keyreq, :kwargs ])
          expect(params).to include([ :keyreq, :context ])
        end
      end
    end
  end

  it "the base Pito::Chat::Handler supplies the contract for every subclass" do
    # A brand-new handler needs no boilerplate to satisfy the contract — the base
    # class's self.call unpacks the context into the existing initializer.
    fake = Class.new(Pito::Chat::Handler) do
      def call
        Pito::Chat::Result::Ok.new(events: [ { kind: :system, payload: { seen: kwargs, period: } } ])
      end
    end

    context = Pito::Dispatch::Context.new(
      message: nil, conversation: Conversation.singleton, period: "28d"
    )
    result = fake.call(kwargs: { ref: :sentinel }, context:)

    expect(result).to be_a(Pito::Chat::Result::Ok)
    expect(result.events.first[:payload]).to eq({ seen: { ref: :sentinel }, period: "28d" })
  end
end
