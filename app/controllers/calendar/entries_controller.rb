# Phase 15 §2 — Calendar Views.
#
# Manual entries CRUD. Derived/auto entries are NOT user-creatable;
# the controller rejects writes outside the manual entry types.
# Read-only enforcement is mirrored from the model layer (the model's
# `read_only?` predicate); the controller redirects with a flash on
# attempted edit/update of a read-only entry. The `note` action is
# the dedicated endpoint for adding `metadata.user_overrides` to
# derived/auto entries.
class Calendar::EntriesController < ApplicationController
  MANUAL_ENTRY_TYPES = %w[game_release purchase_planned milestone_manual custom].freeze
  YES_NO_FIELDS = %i[all_day manual_date_override tba_remind_monthly notify_anyway].freeze

  before_action :load_entry, only: %i[show edit update note]

  def new
    @entry = CalendarEntry.new(
      entry_type: params[:entry_type].presence_in(MANUAL_ENTRY_TYPES) || "milestone_manual",
      starts_at: 1.day.from_now,
      timezone: AppSetting.first&.timezone || "UTC"
    )
  end

  def quick_add
    @entry = CalendarEntry.new(
      entry_type: params[:entry_type].presence_in(MANUAL_ENTRY_TYPES) || "milestone_manual",
      starts_at: 1.day.from_now,
      timezone: AppSetting.first&.timezone || "UTC"
    )
    render :new
  end

  def create
    # Default-create (Projects pattern): when the request carries no
    # `calendar_entry` payload, instantiate a milestone_manual entry
    # with placeholder values and redirect straight to /edit. The `[+]`
    # breadcrumb action posts here with no params; the user fills in
    # real values in the edit form. Deep-link / programmatic access via
    # the regular `new` form still POSTs the full payload and lands on
    # the show page.
    if params[:calendar_entry].blank?
      @entry = CalendarEntry.new(default_create_attributes)
      @entry.source = :manual
      @entry.created_by_user = Current.user
      @entry.save!
      redirect_to edit_calendar_entry_path(@entry), notice: "calendar entry created."
      return
    end

    type = params.dig(:calendar_entry, :entry_type).to_s
    unless MANUAL_ENTRY_TYPES.include?(type)
      flash.now[:alert] = "this entry type is not user-creatable."
      @entry = CalendarEntry.new(entry_type: "milestone_manual")
      render :new, status: :unprocessable_content
      return
    end

    attrs = create_params(type)
    return if performed? # yes/no rejection guard

    @entry = CalendarEntry.new(attrs)
    @entry.source = :manual
    @entry.created_by_user = Current.user

    if @entry.save
      redirect_to calendar_entry_path(@entry), notice: "calendar entry created."
    else
      render :new, status: :unprocessable_content
    end
  end

  def show
    @parent_entry = @entry.parent_entry
    @child_entries = @entry.child_entries.where.not(state: %i[cancelled superseded]).to_a
    @declarations = Calendar::NotificationDispatchDeclaration.declarations_for(@entry)
  end

  def edit
    if @entry.read_only?
      redirect_to calendar_entry_path(@entry),
                  alert: "this entry is read-only — edit the source instead."
      nil
    end
  end

  def update
    if @entry.read_only?
      redirect_to calendar_entry_path(@entry),
                  alert: "this entry is read-only — edit the source instead."
      return
    end

    attrs = update_params(@entry.entry_type)
    return if performed?

    if @entry.update(attrs)
      redirect_to calendar_entry_path(@entry), notice: "calendar entry updated."
    else
      render :edit, status: :unprocessable_content
    end
  end

  # PATCH /calendar/entries/:id/note — derived / auto entries can gain
  # metadata.user_overrides notes through this endpoint without
  # violating the read-only enforcement (open-question #8 decision).
  def note
    # Phase 15 security audit F1: scope the read-only bypass to the
    # `metadata` attribute only. The `metadata_changes_only_user_overrides?`
    # check still runs underneath; the allowlist just exempts the
    # metadata column from the whole-record forbidden-changes check.
    @entry.bypass_readonly_for = [ :metadata ]
    note_text = params.dig(:calendar_entry, :note).to_s
    new_meta = (@entry.metadata || {}).deep_dup
    new_meta["user_overrides"] ||= {}
    new_meta["user_overrides"]["note"] = note_text
    if @entry.update(metadata: new_meta)
      redirect_to calendar_entry_path(@entry), notice: "note saved."
    else
      render :show, status: :unprocessable_content
    end
  end

  private

  def load_entry
    @entry = CalendarEntry.find(params[:id])
  end

  # Default-create attributes for the no-params POST flow (Projects
  # pattern). `milestone_manual` is the default type because it has the
  # loosest validator shape (no required cross-references, no required
  # metadata keys), so the row always saves on the first try and the
  # user can switch type later in the edit form. `starts_at` defaults to
  # the current time so the edit form's datetime picker pre-populates
  # with a sensible value.
  def default_create_attributes
    {
      entry_type: "milestone_manual",
      title: "Untitled event",
      starts_at: Time.current,
      ends_at: nil,
      all_day: false,
      timezone: AppSetting.first&.timezone || "UTC"
    }
  end

  def create_params(type)
    base = params.require(:calendar_entry).permit(
      :title, :description, :starts_at, :ends_at, :all_day, :timezone,
      :entry_type, :parent_entry_id, :game_id, :project_id, :video_id,
      :channel_id, :milestone_rule_id, :manual_date_override,
      :release_precision, :tba_remind_monthly, :notify_anyway,
      metadata: {}
    )
    base[:entry_type] = type
    coerce_yes_no!(base) || base
  end

  def update_params(type)
    base = params.require(:calendar_entry).permit(
      :title, :description, :starts_at, :ends_at, :all_day, :timezone,
      :parent_entry_id, :game_id, :project_id,
      :manual_date_override, :release_precision,
      :tba_remind_monthly, :notify_anyway, metadata: {}
    )
    coerce_yes_no!(base) || base
  end

  # Strict yes/no enforcement per CLAUDE.md hard rule. Stray "true" /
  # "false" / "1" / "0" / boolean instances reject with 422 + flash.
  # Returns false (no halt) on success; renders + halts on failure.
  def coerce_yes_no!(attrs)
    YES_NO_FIELDS.each do |key|
      raw = attrs[key]
      next if raw.nil?
      case raw.to_s
      when "yes" then attrs[key] = true
      when "no"  then attrs[key] = false
      else
        flash.now[:alert] = "invalid yes/no value for #{key}: must be 'yes' or 'no'."
        @entry = CalendarEntry.new(attrs.except(*YES_NO_FIELDS))
        render :new, status: :unprocessable_content
        return nil
      end
    end
    attrs
  end
end
