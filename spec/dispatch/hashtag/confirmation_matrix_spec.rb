# frozen_string_literal: true

require "rails_helper"

# ── Dispatch matrix: confirmation hashtag follow-up (recognition, DB mocked) ──
#
# RULE: every action + command combination the confirmation handler recognises is
# covered here. Pito::Confirmation::Executor is fully stubbed — zero factories,
# zero DB hits, no real execution.
#
# Source event is an instance_double(Event, payload: { reply_target: "confirmation",
#   command: "...", ... }) — no factories.
#
# Canonical actions: confirm, cancel
# Action aliases (ACTION_ALIASES):
#   yes / y / ok / approve / true  → confirm
#   no  / n  / false / discard     → cancel
#
# Commands exercised (all branches in Pito::Confirmation::Executor):
#   sync_videos, sync_channel, sync_channel_videos, sync_game,
#   video_delete, game_delete, video_publish, video_unlist, video_schedule,
#   game_reindex, video_reindex, disconnect, import_videos,
#   unknown_command (fallback else branch)
#
# Event kind routing on confirm:
#   import_videos                        → :system   (SYSTEM_OUTCOME_ON_CONFIRM)
#   video_schedule / video_publish /
#     video_unlist / video_delete        → :enhanced  (ENHANCED_OUTCOME_ON_CONFIRM)
#   all other commands                   → :confirmation_follow_up
#
# Event kind routing on cancel:
#   all commands                         → :confirmation_follow_up
RSpec.describe "Dispatch matrix — confirmation hashtag follow-up (recognition, DB mocked)", type: :dispatch do
  subject(:handler) { Pito::FollowUp::Handlers::Confirmation.new }

  # ── shared doubles ────────────────────────────────────────────────────────────

  let(:conversation) { instance_double(Conversation) }

  # Build a minimal confirmation event payload for the given command.
  def event_for(command, extra = {})
    payload = {
      "reply_target" => "confirmation",
      "reply_handle" => "zz-9999",
      "command"      => command,
      "body"         => "Confirm #{command}?"
    }.merge(extra.transform_keys(&:to_s))
    instance_double(Event, payload: payload)
  end

  # Convenience: call the handler with the given event + action string.
  def call(event, rest)
    handler.call(event: event, rest: rest, conversation: conversation)
  end

  # Default executor stubs — prevent any real DB/job access.
  before do
    allow(Pito::Confirmation::Executor).to receive(:confirm).and_return("confirm outcome text")
    allow(Pito::Confirmation::Executor).to receive(:cancel).and_return("cancel outcome text")
  end

  # ── Class-level declarations ──────────────────────────────────────────────────

  describe "class declarations" do
    it "target is 'confirmation'" do
      expect(Pito::FollowUp::Handlers::Confirmation.target).to eq("confirmation")
    end

    it "Matrix serves :append mode for confirmation" do
      expect(Pito::Dispatch::Matrix.mode_for("confirmation")).to eq(:append)
    end

    it "Matrix advertises 'confirm' and 'cancel' for confirmation" do
      expect(Pito::Dispatch::Matrix.actions_for("confirmation")).to include("confirm", "cancel")
    end

    it "VALID_ACTIONS contains confirm and cancel" do
      expect(Pito::FollowUp::Handlers::Confirmation::VALID_ACTIONS).to match_array(%w[confirm cancel])
    end

    it "SYSTEM_OUTCOME_ON_CONFIRM contains import_videos" do
      expect(Pito::FollowUp::Handlers::Confirmation::SYSTEM_OUTCOME_ON_CONFIRM).to include("import_videos")
    end

    it "ENHANCED_OUTCOME_ON_CONFIRM contains the video write-through commands" do
      expected = %w[video_schedule video_schedule_mass video_publish video_unlist video_delete video_metadata video_metadata_mass]
      expect(Pito::FollowUp::Handlers::Confirmation::ENHANCED_OUTCOME_ON_CONFIRM)
        .to match_array(expected)
    end

    it "ACTION_ALIASES maps all confirm synonyms" do
      aliases = Pito::FollowUp::Handlers::Confirmation::ACTION_ALIASES
      expect(aliases).to include(
        "yes" => "confirm", "y" => "confirm", "ok" => "confirm",
        "approve" => "confirm", "true" => "confirm"
      )
    end

    it "ACTION_ALIASES maps all cancel synonyms" do
      aliases = Pito::FollowUp::Handlers::Confirmation::ACTION_ALIASES
      expect(aliases).to include(
        "no" => "cancel", "n" => "cancel", "false" => "cancel", "discard" => "cancel"
      )
    end
  end

  # ── Result type on any valid action ──────────────────────────────────────────

  describe "any valid action → Result::Append" do
    let(:event) { event_for("disconnect") }

    %w[confirm cancel yes no y n ok approve true false discard].each do |action|
      it "#{action.inspect} → Result::Append" do
        expect(call(event, action)).to be_a(Pito::FollowUp::Result::Append)
      end
    end

    it "Result::Append carries exactly one event" do
      expect(call(event, "confirm").events.size).to eq(1)
      expect(call(event, "cancel").events.size).to eq(1)
    end
  end

  # ── Executor routing — confirm (canonical + all aliases) ─────────────────────
  #
  # Every confirm-flavoured word must call Executor.confirm, never Executor.cancel.

  describe "confirm branch — Executor.confirm is called" do
    let(:event) { event_for("disconnect") }

    {
      "confirm"  => "canonical",
      "yes"      => "alias",
      "y"        => "alias",
      "ok"       => "alias",
      "approve"  => "alias",
      "true"     => "alias"
    }.each do |action, kind|
      it "#{action.inspect} (#{kind}) calls Executor.confirm" do
        call(event, action)
        expect(Pito::Confirmation::Executor).to have_received(:confirm)
        expect(Pito::Confirmation::Executor).not_to have_received(:cancel)
      end
    end
  end

  # ── Executor routing — cancel (canonical + all aliases) ──────────────────────
  #
  # Every cancel-flavoured word must call Executor.cancel, never Executor.confirm.

  describe "cancel branch — Executor.cancel is called" do
    let(:event) { event_for("disconnect") }

    {
      "cancel"  => "canonical",
      "no"      => "alias",
      "n"       => "alias",
      "false"   => "alias",
      "discard" => "alias"
    }.each do |action, kind|
      it "#{action.inspect} (#{kind}) calls Executor.cancel" do
        call(event, action)
        expect(Pito::Confirmation::Executor).to have_received(:cancel)
        expect(Pito::Confirmation::Executor).not_to have_received(:confirm)
      end
    end
  end

  # ── Executor receives the correct command string ──────────────────────────────
  #
  # The handler extracts command from event.payload["command"] and passes it as
  # the first arg to Executor.confirm / .cancel.

  describe "Executor receives command from payload" do
    %w[
      sync_videos sync_channel sync_channel_videos sync_game
      video_delete game_delete video_publish video_unlist video_schedule
      game_reindex video_reindex disconnect import_videos unknown_command
    ].each do |command|
      it "confirm with command #{command.inspect} → Executor.confirm(#{command.inspect}, ...)" do
        call(event_for(command), "confirm")
        expect(Pito::Confirmation::Executor).to have_received(:confirm).with(command, anything)
      end

      it "cancel with command #{command.inspect} → Executor.cancel(#{command.inspect}, ...)" do
        call(event_for(command), "cancel")
        expect(Pito::Confirmation::Executor).to have_received(:cancel).with(command, anything)
      end
    end
  end

  # ── Event kind routing on confirm ────────────────────────────────────────────
  #
  # SYSTEM_OUTCOME_ON_CONFIRM:  import_videos            → kind: "system"
  # ENHANCED_OUTCOME_ON_CONFIRM: video_schedule/publish/
  #                               unlist/delete           → kind: "enhanced"
  # All others                                           → kind: "confirmation_follow_up"

  describe "event kind routing on confirm" do
    # Standard commands → confirmation_follow_up
    standard_commands = %w[
      sync_videos sync_channel sync_channel_videos sync_game
      game_delete game_reindex video_reindex disconnect unknown_command
    ]

    describe "standard commands → confirmation_follow_up" do
      standard_commands.each do |command|
        it "#{command.inspect} + confirm → kind: 'confirmation_follow_up'" do
          result = call(event_for(command), "confirm")
          expect(result.events.first[:kind]).to eq(:confirmation_follow_up)
        end
      end
    end

    # import_videos → system (SYSTEM_OUTCOME_ON_CONFIRM)
    describe "import_videos → :system (SYSTEM_OUTCOME_ON_CONFIRM)" do
      it "import_videos + confirm → kind: 'system'" do
        result = call(event_for("import_videos"), "confirm")
        expect(result.events.first[:kind]).to eq(:system)
      end

      it "import_videos system event carries 'text' in payload" do
        result = call(event_for("import_videos"), "confirm")
        expect(result.events.first[:payload]).to have_key("text")
      end

      it "import_videos system event outcome_text comes from Executor" do
        result = call(event_for("import_videos"), "confirm")
        expect(result.events.first[:payload]["text"]).to eq("confirm outcome text")
      end
    end

    # ENHANCED_OUTCOME_ON_CONFIRM commands → enhanced
    enhanced_commands = %w[video_schedule video_publish video_unlist video_delete]

    describe "ENHANCED_OUTCOME_ON_CONFIRM commands → :enhanced" do
      enhanced_commands.each do |command|
        it "#{command.inspect} + confirm → kind: 'enhanced'" do
          result = call(event_for(command), "confirm")
          expect(result.events.first[:kind]).to eq(:enhanced)
        end

        it "#{command.inspect} enhanced event carries 'text' in payload" do
          result = call(event_for(command), "confirm")
          expect(result.events.first[:payload]).to have_key("text")
        end

        it "#{command.inspect} enhanced event outcome_text comes from Executor" do
          result = call(event_for(command), "confirm")
          expect(result.events.first[:payload]["text"]).to eq("confirm outcome text")
        end
      end
    end
  end

  # ── Event kind routing on cancel ─────────────────────────────────────────────
  #
  # Cancel always yields confirmation_follow_up, for every command.
  # (No SYSTEM or ENHANCED overrides on the cancel path.)

  describe "event kind routing on cancel — always confirmation_follow_up" do
    all_commands = %w[
      sync_videos sync_channel sync_channel_videos sync_game
      video_delete game_delete video_publish video_unlist video_schedule
      game_reindex video_reindex disconnect import_videos unknown_command
    ]

    all_commands.each do |command|
      it "#{command.inspect} + cancel → kind: 'confirmation_follow_up'" do
        result = call(event_for(command), "cancel")
        expect(result.events.first[:kind]).to eq(:confirmation_follow_up)
      end
    end
  end

  # ── confirmation_follow_up payload structure ──────────────────────────────────

  describe "confirmation_follow_up payload structure" do
    let(:event) { event_for("disconnect") }

    describe "on confirm" do
      subject(:event_payload) { call(event, "confirm").events.first[:payload] }

      it "includes command: 'disconnect'" do
        expect(event_payload[:command]).to eq("disconnect")
      end

      it "includes outcome: 'confirm'" do
        expect(event_payload[:outcome]).to eq("confirm")
      end

      it "includes outcome_text from Executor" do
        expect(event_payload[:outcome_text]).to eq("confirm outcome text")
      end

      it "includes resolved: true" do
        expect(event_payload[:resolved]).to be(true)
      end
    end

    describe "on cancel" do
      subject(:event_payload) { call(event, "cancel").events.first[:payload] }

      it "includes command: 'disconnect'" do
        expect(event_payload[:command]).to eq("disconnect")
      end

      it "includes outcome: 'cancel'" do
        expect(event_payload[:outcome]).to eq("cancel")
      end

      it "includes outcome_text from Executor" do
        expect(event_payload[:outcome_text]).to eq("cancel outcome text")
      end

      it "includes resolved: true" do
        expect(event_payload[:resolved]).to be(true)
      end
    end

    describe "aliases preserve canonical outcome in payload" do
      # Alias resolution must normalise before building the event payload.
      it "yes → outcome: 'confirm' (not 'yes')" do
        result = call(event, "yes")
        expect(result.events.first[:payload][:outcome]).to eq("confirm")
      end

      it "no → outcome: 'cancel' (not 'no')" do
        result = call(event, "no")
        expect(result.events.first[:payload][:outcome]).to eq("cancel")
      end

      it "ok → outcome: 'confirm'" do
        expect(call(event, "ok").events.first[:payload][:outcome]).to eq("confirm")
      end

      it "approve → outcome: 'confirm'" do
        expect(call(event, "approve").events.first[:payload][:outcome]).to eq("confirm")
      end

      it "true → outcome: 'confirm'" do
        expect(call(event, "true").events.first[:payload][:outcome]).to eq("confirm")
      end

      it "y → outcome: 'confirm'" do
        expect(call(event, "y").events.first[:payload][:outcome]).to eq("confirm")
      end

      it "n → outcome: 'cancel'" do
        expect(call(event, "n").events.first[:payload][:outcome]).to eq("cancel")
      end

      it "false → outcome: 'cancel'" do
        expect(call(event, "false").events.first[:payload][:outcome]).to eq("cancel")
      end

      it "discard → outcome: 'cancel'" do
        expect(call(event, "discard").events.first[:payload][:outcome]).to eq("cancel")
      end
    end
  end

  # ── Result::Append consume flag ───────────────────────────────────────────────

  describe "Result::Append consume flag" do
    let(:event) { event_for("disconnect") }

    it "confirm result has consume: true (source event is consumed)" do
      expect(call(event, "confirm").consume).to be(true)
    end

    it "cancel result has consume: true (source event is consumed)" do
      expect(call(event, "cancel").consume).to be(true)
    end
  end

  # ── Unknown action → Result::Error ───────────────────────────────────────────
  #
  # Any word not in VALID_ACTIONS and not in ACTION_ALIASES must return an Error.

  describe "unknown action → Result::Error" do
    let(:event) { event_for("disconnect") }

    unknown_tools = %w[bogus destroy publish reindex sync import yes_please 999 banana]

    unknown_tools.each do |bad|
      it "#{bad.inspect} → Result::Error (not Append)" do
        result = call(event, bad)
        expect(result).to be_a(Pito::FollowUp::Result::Error)
      end

      it "#{bad.inspect} → error key is pito.confirmation.errors.invalid_action" do
        result = call(event, bad)
        expect(result.message_key).to eq("pito.confirmation.errors.invalid_action")
      end

      it "#{bad.inspect} → message_args includes the offending action word" do
        result = call(event, bad)
        expect(result.message_args).to include(action: bad)
      end

      it "#{bad.inspect} → Executor.confirm is NOT called" do
        call(event, bad)
        expect(Pito::Confirmation::Executor).not_to have_received(:confirm)
      end

      it "#{bad.inspect} → Executor.cancel is NOT called" do
        call(event, bad)
        expect(Pito::Confirmation::Executor).not_to have_received(:cancel)
      end
    end

    it "empty action string → Result::Error" do
      result = call(event, "")
      expect(result).to be_a(Pito::FollowUp::Result::Error)
    end

    it "whitespace-only action string → Result::Error" do
      result = call(event, "   ")
      expect(result).to be_a(Pito::FollowUp::Result::Error)
    end
  end

  # ── Executor raises → graceful Result::Append ────────────────────────────────
  #
  # StandardError from either executor branch is caught; handler returns
  # Result::Append (not Error) with the execution_failed copy text.

  describe "Executor raises StandardError → graceful Result::Append" do
    let(:event) { event_for("disconnect") }

    context "Executor.confirm raises" do
      before { allow(Pito::Confirmation::Executor).to receive(:confirm).and_raise(StandardError, "boom") }

      it "returns Result::Append (not Result::Error)" do
        expect(call(event, "confirm")).to be_a(Pito::FollowUp::Result::Append)
      end

      it "appended event carries the execution_failed copy text" do
        result = call(event, "confirm")
        outcome_text = result.events.first[:payload][:outcome_text]
        expect(outcome_text).to include(Pito::Copy.render("pito.copy.confirmation.execution_failed"))
      end
    end

    context "Executor.cancel raises" do
      before { allow(Pito::Confirmation::Executor).to receive(:cancel).and_raise(StandardError, "db gone") }

      it "returns Result::Append (not Result::Error)" do
        expect(call(event, "cancel")).to be_a(Pito::FollowUp::Result::Append)
      end

      it "appended event carries the execution_failed copy text" do
        result = call(event, "cancel")
        outcome_text = result.events.first[:payload][:outcome_text]
        expect(outcome_text).to include(Pito::Copy.render("pito.copy.confirmation.execution_failed"))
      end
    end

    context "Executor.confirm raises with an alias" do
      before { allow(Pito::Confirmation::Executor).to receive(:confirm).and_raise(StandardError, "db error") }

      it "yes (alias) still yields graceful Result::Append" do
        expect(call(event, "yes")).to be_a(Pito::FollowUp::Result::Append)
      end
    end
  end

  # ── Registry integration ──────────────────────────────────────────────────────

  describe "Registry integration" do
    before { Pito::FollowUp::Registry.register_all! }

    it "confirmation is registered in the Registry" do
      expect(Pito::FollowUp::Registry.for("confirmation")).to eq(Pito::FollowUp::Handlers::Confirmation)
    end

    it "mode_for 'confirmation' (no action) is :append" do
      expect(Pito::FollowUp::Registry.mode_for("confirmation")).to eq(:append)
    end

    it "mode_for 'confirmation' confirm is :append" do
      expect(Pito::FollowUp::Registry.mode_for("confirmation", action: "confirm")).to eq(:append)
    end

    it "mode_for 'confirmation' cancel is :append" do
      expect(Pito::FollowUp::Registry.mode_for("confirmation", action: "cancel")).to eq(:append)
    end

    it "actions_for 'confirmation' returns confirm and cancel" do
      expect(Pito::FollowUp::Registry.actions_for("confirmation").map(&:to_s))
        .to match_array(%w[confirm cancel])
    end
  end
end
