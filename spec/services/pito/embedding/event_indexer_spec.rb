# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Embedding::EventIndexer, type: :service do
  let(:client) { instance_double(Pito::Embedding::Client) }
  let(:embedder_url) { "http://127.0.0.1:8091" }

  def set_embedder_url(value)
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("PITO_EMBEDDER_URL").and_return(value)
  end

  def build_event(kind:, payload: { "text" => "Some searchable scrollback content." })
    create(:event, kind: kind, payload: payload)
  end

  before do
    set_embedder_url(embedder_url)
    allow(Pito::Embedding::Client).to receive(:new).and_return(client)
    allow(client).to receive(:embed).and_return([ Array.new(768, 0.1) ])
  end

  it "embeds an allowlisted kind and persists embedding + digest without touching updated_at" do
    event = build_event(kind: "echo")
    original_updated_at = event.updated_at

    expect { described_class.call(event) }
      .to change { event.reload.embedded_digest }.from(nil)
    expect(event.embedding).to be_present
    expect(event.updated_at).to eq(original_updated_at)
  end

  it "no-ops without a client call for a non-allowlisted kind (e.g. error)" do
    event = build_event(kind: "error", payload: { "message_key" => "pito.copy.x.y" })
    expect(Pito::Embedding::Client).not_to receive(:new)

    expect { described_class.call(event) }
      .not_to change { event.reload.embedded_digest }
    expect(event.embedding).not_to be_present
  end

  it "no-ops without a client call when the projected text is blank" do
    event = build_event(kind: "system", payload: {})
    expect(Pito::Embedding::Client).not_to receive(:new)

    expect { described_class.call(event) }
      .not_to change { event.reload.embedded_digest }
    expect(event.embedding).not_to be_present
  end

  it "no-ops when the digest is unchanged" do
    event = build_event(kind: "echo")
    described_class.call(event)

    expect(client).not_to receive(:embed)
    described_class.call(event.reload)
  end

  it "force: re-embeds even when the digest is unchanged" do
    event = build_event(kind: "echo")
    described_class.call(event)

    expect(client).to receive(:embed).and_return([ Array.new(768, 0.3) ])
    described_class.call(event.reload, force: true)
  end

  it "no-ops without an HTTP call when PITO_EMBEDDER_URL is blank" do
    event = build_event(kind: "echo")
    set_embedder_url(nil)
    expect(Pito::Embedding::Client).not_to receive(:new)

    expect { described_class.call(event) }
      .not_to change { event.reload.embedded_digest }
    expect(event.embedding).not_to be_present
  end

  it "does not raise and does not write when the client returns a nil embedding" do
    event = build_event(kind: "echo")
    allow(client).to receive(:embed).and_return([ nil ])

    expect { described_class.call(event) }.not_to raise_error
    expect(event.reload.embedded_digest).to be_nil
    expect(event.embedding).not_to be_present
  end
end
