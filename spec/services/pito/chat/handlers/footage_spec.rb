# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Chat::Handlers::Footage do
  def tokens(*words)
    words.each_with_index.map do |w, i|
      Pito::Lex::Token.new(type: :word, value: w, position: i, preceded_by_space: i.positive?)
    end
  end

  def handler_for(*words)
    described_class.new(
      message: Pito::Chat::Message.new(
        verb: :footage,
        body_tokens: tokens(*words),
        kind: :new_turn,
        raw: "footage #{words.join(' ')}".strip
      ),
      conversation: Conversation.singleton
    )
  end

  let!(:game) { create(:game, title: "Pragmata") }

  # ── footage update <id> <hours> — success ────────────────────────────────────

  it "sets the game's footage_hours and returns an Ok system confirmation" do
    result = handler_for("update", game.id.to_s, "12.5").call

    expect(result).to be_a(Pito::Chat::Result::Ok)
    expect(game.reload.footage_hours).to eq(BigDecimal("12.5"))

    event = result.events.first
    expect(event[:kind]).to eq(:system)
    expect(event[:payload]["text"]).to include("Pragmata").and include("12.5h")
  end

  it "renders whole-hour totals without a trailing .0 in the confirmation" do
    result = handler_for("update", game.id.to_s, "5").call

    expect(game.reload.footage_hours).to eq(BigDecimal("5.0"))
    expect(result.events.first[:payload]["text"]).to include("5h")
  end

  # ── ceil UP to the next 0.5 (BigDecimal-exact) ───────────────────────────────

  it "ceils a fractional value up to the next half-hour (12.3 → 12.5)" do
    handler_for("update", game.id.to_s, "12.3").call
    expect(game.reload.footage_hours).to eq(BigDecimal("12.5"))
  end

  it "ceils just past a half-step up to the next whole hour (8.51 → 9.0)" do
    handler_for("update", game.id.to_s, "8.51").call
    expect(game.reload.footage_hours).to eq(BigDecimal("9.0"))
  end

  it "leaves an exact whole number on a clean step (5 → 5.0)" do
    handler_for("update", game.id.to_s, "5").call
    expect(game.reload.footage_hours).to eq(BigDecimal("5.0"))
  end

  it "leaves an exact half-step untouched (2.5 → 2.5)" do
    handler_for("update", game.id.to_s, "2.5").call
    expect(game.reload.footage_hours).to eq(BigDecimal("2.5"))
  end

  # ── id resolution: numeric only, with optional `#` prefix ────────────────────

  it "resolves the game by bare numeric id" do
    result = handler_for("update", game.id.to_s, "3").call
    expect(result).to be_a(Pito::Chat::Result::Ok)
    expect(game.reload.footage_hours).to eq(BigDecimal("3.0"))
  end

  it "resolves the game by #N id form" do
    result = handler_for("update", "##{game.id}", "3").call
    expect(result).to be_a(Pito::Chat::Result::Ok)
    expect(game.reload.footage_hours).to eq(BigDecimal("3.0"))
  end

  # ── footage snippet ──────────────────────────────────────────────────────────

  it "emits a system event rendering the copyable snippet command" do
    result = handler_for("snippet").call

    expect(result).to be_a(Pito::Chat::Result::Ok)

    event = result.events.first
    expect(event[:kind]).to eq(:system)
    expect(event[:payload]["html"]).to be(true)

    fragment = Nokogiri::HTML.fragment(event[:payload]["body"])
    code     = fragment.css(".pito-footage-snippet__code").first
    expect(code.text).to eq(Pito::Footage::SnippetComponent::COMMAND)
  end

  it "renders the snippet message with the clipboard wiring" do
    result = handler_for("snippet").call
    body   = result.events.first[:payload]["body"]

    expect(body).to include('data-controller="pito--clipboard"')
    expect(body).to include("click->pito--clipboard#copy")
  end

  # ── unknown / non-numeric reference → witty not-found ────────────────────────

  it "returns a witty not-found (text payload) for an unknown numeric id" do
    result = handler_for("update", "9999999", "5").call
    expect(result).to be_a(Pito::Chat::Result::Ok)
    expect(result.events.first[:payload]["text"]).to be_present
  end

  it "returns a witty not-found for a non-numeric (title-style) reference" do
    result = handler_for("update", "Pragmata", "5").call
    expect(result).to be_a(Pito::Chat::Result::Ok)
    expect(result.events.first[:payload]["text"]).to be_present
    expect(game.reload.footage_hours).to eq(BigDecimal(0))
  end

  # ── missing / short args → usage hint ────────────────────────────────────────

  it "returns needs_ref when no args are given" do
    result = handler_for.call
    expect(result).to be_a(Pito::Chat::Result::Error)
    expect(result.message_key).to eq("pito.chat.footage.needs_ref")
  end

  it "returns needs_ref for an unknown subcommand" do
    result = handler_for("tally", game.id.to_s).call
    expect(result).to be_a(Pito::Chat::Result::Error)
    expect(result.message_key).to eq("pito.chat.footage.needs_ref")
  end

  it "names both the update and snippet forms in the usage hint copy" do
    hint = I18n.t("pito.chat.footage.needs_ref")
    expect(hint).to include("footage update <id> <hours>")
    expect(hint).to include("footage snippet")
  end

  it "returns needs_ref when the subcommand is missing (only an id)" do
    result = handler_for(game.id.to_s).call
    expect(result).to be_a(Pito::Chat::Result::Error)
    expect(result.message_key).to eq("pito.chat.footage.needs_ref")
  end

  it "returns needs_ref when the hours value is missing" do
    result = handler_for("update", game.id.to_s).call
    expect(result).to be_a(Pito::Chat::Result::Error)
    expect(result.message_key).to eq("pito.chat.footage.needs_ref")
  end

  # ── invalid hours → usage hint ───────────────────────────────────────────────

  it "returns needs_ref for non-numeric hours" do
    result = handler_for("update", game.id.to_s, "soon").call
    expect(result).to be_a(Pito::Chat::Result::Error)
    expect(result.message_key).to eq("pito.chat.footage.needs_ref")
    expect(game.reload.footage_hours).to eq(BigDecimal(0))
  end

  it "returns needs_ref for negative hours" do
    result = handler_for("update", game.id.to_s, "-3").call
    expect(result).to be_a(Pito::Chat::Result::Error)
    expect(result.message_key).to eq("pito.chat.footage.needs_ref")
    expect(game.reload.footage_hours).to eq(BigDecimal(0))
  end
end
