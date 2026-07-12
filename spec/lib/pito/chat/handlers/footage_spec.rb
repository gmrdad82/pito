# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Chat::Handlers::Footage do
  def tokens(*words)
    words.each_with_index.map do |w, i|
      Pito::Lex::Token.new(type: :word, value: w, position: i, preceded_by_space: i.positive?)
    end
  end

  def handler_for(*words, follow_up: nil)
    described_class.new(
      message: Pito::Chat::Message.new(
        tool: :footage,
        body_tokens: tokens(*words),
        kind: :new_turn,
        raw: "footage #{words.join(' ')}".strip
      ),
      conversation: Conversation.singleton,
      follow_up: follow_up
    )
  end

  # A follow-up reply context (e.g. `#g3 footage update 3 12.5`). Footage reads
  # ONLY message.raw for resolution (parse_args) — the context's source_event
  # and rest are never consulted — so a minimal stub is enough to flip
  # `follow_up?` true and exercise the preserved write path.
  def reply_context
    Pito::Chat::FollowUpContext.new(source_event: instance_double(Event, payload: {}), rest: "")
  end

  let!(:game) { create(:game, title: "Pragmata") }

  # ── footage update <id> <hours> in free chat — moved to `update` ─────────────

  it "returns a moved error (not a write) for the typed setter in free chat" do
    result = handler_for("update", game.id.to_s, "12.5").call

    expect(result).to be_a(Pito::Chat::Result::Error)
    expect(result.message_key).to eq("pito.chat.update.moved")
    expect(result.message_args).to eq(example: "update game footage 12 8.5")
    expect(game.reload.footage_hours).to eq(BigDecimal(0))
  end

  it "returns moved even with missing/invalid operands (no needs_ref fallback)" do
    result = handler_for("update").call

    expect(result).to be_a(Pito::Chat::Result::Error)
    expect(result.message_key).to eq("pito.chat.update.moved")
  end

  it "never touches Game for a typed update attempt in free chat" do
    expect(::Game).not_to receive(:find_by)
    handler_for("update", game.id.to_s, "5").call
  end

  # ── footage update <id> <hours> via a follow-up reply — write path preserved ─

  it "sets the game's footage_hours and returns an Ok system confirmation" do
    result = handler_for("update", game.id.to_s, "12.5", follow_up: reply_context).call

    expect(result).to be_a(Pito::Chat::Result::Ok)
    expect(game.reload.footage_hours).to eq(BigDecimal("12.5"))

    event = result.events.first
    expect(event[:kind]).to eq(:system)
    expect(event[:payload]["text"]).to include("Pragmata").and include("12.5h")
  end

  it "renders whole-hour totals without a trailing .0 in the confirmation" do
    result = handler_for("update", game.id.to_s, "5", follow_up: reply_context).call

    expect(game.reload.footage_hours).to eq(BigDecimal("5.0"))
    expect(result.events.first[:payload]["text"]).to include("5h")
  end

  # ── ceil UP to the next 0.5 (BigDecimal-exact) ───────────────────────────────

  it "ceils a fractional value up to the next half-hour (12.3 → 12.5)" do
    handler_for("update", game.id.to_s, "12.3", follow_up: reply_context).call
    expect(game.reload.footage_hours).to eq(BigDecimal("12.5"))
  end

  it "ceils just past a half-step up to the next whole hour (8.51 → 9.0)" do
    handler_for("update", game.id.to_s, "8.51", follow_up: reply_context).call
    expect(game.reload.footage_hours).to eq(BigDecimal("9.0"))
  end

  it "leaves an exact whole number on a clean step (5 → 5.0)" do
    handler_for("update", game.id.to_s, "5", follow_up: reply_context).call
    expect(game.reload.footage_hours).to eq(BigDecimal("5.0"))
  end

  it "leaves an exact half-step untouched (2.5 → 2.5)" do
    handler_for("update", game.id.to_s, "2.5", follow_up: reply_context).call
    expect(game.reload.footage_hours).to eq(BigDecimal("2.5"))
  end

  # ── id resolution: numeric only, with optional `#` prefix ────────────────────

  it "resolves the game by bare numeric id" do
    result = handler_for("update", game.id.to_s, "3", follow_up: reply_context).call
    expect(result).to be_a(Pito::Chat::Result::Ok)
    expect(game.reload.footage_hours).to eq(BigDecimal("3.0"))
  end

  it "resolves the game by #N id form" do
    result = handler_for("update", "##{game.id}", "3", follow_up: reply_context).call
    expect(result).to be_a(Pito::Chat::Result::Ok)
    expect(game.reload.footage_hours).to eq(BigDecimal("3.0"))
  end

  # ── footage game <id> — same Ok as `footage snippet` ─────────────────────────

  it "treats `footage game <id>` as the snippet command (id is not consulted)" do
    result = handler_for("game", game.id.to_s).call

    expect(result).to be_a(Pito::Chat::Result::Ok)

    event = result.events.first
    expect(event[:kind]).to eq(:system)
    expect(event[:payload]["html"]).to be(true)

    fragment = Nokogiri::HTML.fragment(event[:payload]["body"])
    code     = fragment.css(".pito-footage-snippet__code").first
    expect(code.text).to eq(Pito::Footage::SnippetComponent::COMMAND)
  end

  it "never touches Game for `footage game <id>` (no write, no lookup)" do
    expect(::Game).not_to receive(:find_by)
    handler_for("game", game.id.to_s).call
    expect(game.reload.footage_hours).to eq(BigDecimal(0))
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

  # ── unknown / non-numeric reference → witty not-found (via follow-up) ───────

  it "returns a witty not-found (text payload) for an unknown numeric id" do
    result = handler_for("update", "9999999", "5", follow_up: reply_context).call
    expect(result).to be_a(Pito::Chat::Result::Ok)
    expect(result.events.first[:payload]["text"]).to be_present
  end

  it "returns a witty not-found for a non-numeric (title-style) reference" do
    result = handler_for("update", "Pragmata", "5", follow_up: reply_context).call
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

  it "names the game/snippet forms and the update verb in the usage hint copy" do
    hint = I18n.t("pito.chat.footage.needs_ref")
    expect(hint).to include("footage game <id>")
    expect(hint).to include("footage snippet")
    expect(hint).to include("update game footage <id> <hours>")
  end

  it "returns needs_ref when the subcommand is missing (only an id)" do
    result = handler_for(game.id.to_s).call
    expect(result).to be_a(Pito::Chat::Result::Error)
    expect(result.message_key).to eq("pito.chat.footage.needs_ref")
  end

  it "returns needs_ref when the hours value is missing (follow-up update)" do
    result = handler_for("update", game.id.to_s, follow_up: reply_context).call
    expect(result).to be_a(Pito::Chat::Result::Error)
    expect(result.message_key).to eq("pito.chat.footage.needs_ref")
  end

  # ── invalid hours → usage hint (via follow-up) ───────────────────────────────

  it "returns needs_ref for non-numeric hours" do
    result = handler_for("update", game.id.to_s, "soon", follow_up: reply_context).call
    expect(result).to be_a(Pito::Chat::Result::Error)
    expect(result.message_key).to eq("pito.chat.footage.needs_ref")
    expect(game.reload.footage_hours).to eq(BigDecimal(0))
  end

  it "returns needs_ref for negative hours" do
    result = handler_for("update", game.id.to_s, "-3", follow_up: reply_context).call
    expect(result).to be_a(Pito::Chat::Result::Error)
    expect(result.message_key).to eq("pito.chat.footage.needs_ref")
    expect(game.reload.footage_hours).to eq(BigDecimal(0))
  end
end
