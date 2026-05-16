# Channel read-only conversion (Unit A0)

## Goal

Convert the channel surface into a strictly one-way, read-only mirror: YouTube
to pito. pito never writes channel attributes back to YouTube. Every surface
that exists to edit a channel or to reconcile a channel diff is dead code and
must be removed: the live-preview machinery, the editable channel-fields form,
the banner-upload affordance, the watermark editor, and the entire `ChannelDiff`
reconciliation surface (model, table, controller actions, routes, views, jobs
branch, services, notification template). The one-way sync pull, the `star`
toggle, the URL-lock, per-channel analytics, the Google connection panel, links
display, the videos table, and the `ChannelChangeLog` history surface all stay.

This is unit A0 of Lane A in the beta-2 roadmap. It runs first, before the
A-channels polish audit, so the audit examines the post-cut surface. It is NOT
audit-first: this architect spec goes straight to `pito-rails` implementation.
An ADR under `docs/decisions/` recording the one-way channel model is authored
separately by the architect (not by `pito-rails`); this spec does not block on
it.

The user of this change is anyone touching the channel surface: the read-only
mirror is simpler, has no write-path failure modes, and no longer carries a
YouTube-push quota cost.

## Scope boundaries

- Spec covers the **Rails web app only**.
- **TUI: nothing to cut.** See the "Cross-stack scope" section — the `pito`
  CLI's `update_channel` is already star-only and there is no channel edit/diff
  surface in the TUI. The master agent does NOT need to dispatch `pito-rust` for
  A0.
- **MCP: not touched.** `channel_diff_show`, `channel_diff_apply`, and the
  star-narrowing of `update_channel` are deferred-cut items recorded in the
  roadmap's scope amendment. A0 leaves `app/mcp/` untouched. See "Cross-stack
  scope".
- **`ChannelChangeLog` / `/channels/:id/history`: KEEP ALL OF IT.** It is the
  read-only mirror's audit trail. It has been verified independent of
  `ChannelDiff` and of the edit form (see "Decoupling verification").
- The video thumbnail preview is a video-side surface; A0 does not touch it.
- DB columns `title_changed_at`, `handle_changed_at`, `watermark_url`,
  `watermark_timing`, `watermark_offset_ms`, `keywords`, `country`,
  `default_language`, `links` are **kept** (no column-drop migration for them).
  They are harmless cached columns; `ChannelSync#fetch_channel` may still
  populate a subset. Dropping them is out of A0 scope and would expand the
  migration surface. Only the `channel_diffs` **table** is dropped. See "Open
  questions" for the rationale call.

## Files touched

### Delete

Web — diff reconciliation surface:

- `app/models/channel_diff.rb`
- `app/controllers/channels/previews_controller.rb`
- `app/services/channels/diff_apply.rb`
- `app/services/channels/diff_computer.rb`
- `app/services/channels/diff_persister.rb`
- `app/jobs/channel_diff_check_job.rb`
- `app/views/channels/diff.html.erb`
- `app/views/channels/_open_diff_banner.html.erb`
- `app/views/channels/_in_sync_banner.html.erb`
- `app/services/notification_formatter/templates/channel_diff_detected.rb`

Web — edit / preview / banner / watermark machinery:

- `app/components/channel_preview_component.rb`
- `app/components/channel_preview_component.html.erb`
- `app/components/watermark_preview_component.rb`
- `app/components/watermark_preview_component.html.erb`
- `app/views/channels/edit.html.erb`
- `app/views/channels/_form.html.erb`
- `app/views/channels/_form_errors.html.erb`
- `app/views/channels/_banner_upload.html.erb`
- `app/views/channels/banner_updated.turbo_stream.erb`
- `app/javascript/controllers/channel_preview_controller.js`
- `app/javascript/controllers/banner_upload_controller.js`
- `app/javascript/controllers/links_repeater_controller.js`
- `app/javascript/controllers/reminder_link_controller.js`

Web — helper that only fed `app/helpers/preview_helper.rb`'s preview path
(verify before delete — see "Decoupling verification" item 5):

- `app/helpers/preview_helper.rb` — delete ONLY if grep confirms it is consumed
  exclusively by `ChannelPreviewComponent` / `WatermarkPreviewComponent` / the
  preview controller. If any surviving view or component renders through it,
  keep the file and strip only the channel-preview-specific methods.

Migration:

- A new drop migration for the `channel_diffs` table (see "Drop migration
  outline"). `pito-rails` authors the migration file; this spec describes it.

Specs to delete outright:

- `spec/models/channel_diff_spec.rb`
- `spec/factories/channel_diffs.rb`
- `spec/jobs/channel_diff_check_job_spec.rb`
- `spec/services/channels/diff_apply_spec.rb`
- `spec/services/channels/diff_persister_spec.rb`
- `spec/requests/channels/diff_spec.rb`
- `spec/system/channel_diff_resolution_spec.rb`
- `spec/components/channel_preview_component_spec.rb`
- `spec/components/watermark_preview_component_spec.rb`
- `spec/requests/channels/previews_spec.rb`
- `spec/system/channel_preview_spec.rb`
- `spec/requests/channels/edit_form_spec.rb`
- `spec/system/channel_edit_form_spec.rb`
- `spec/system/channel_banner_upload_spec.rb`
- `spec/system/channels/watermark_preview_spec.rb`
- `spec/system/calendar_reminder_spec.rb` — verify scope first. If it ONLY
  exercises the channel-edit reminder-link flow, delete it. If it also covers a
  calendar-side reminder surface unrelated to the channel edit form, instead
  rewrite it to drop the channel-edit-driven examples and keep the rest. Grep
  `calendar_reminder_spec.rb` for `edit_channel` / `reminder-link` /
  `channel-preview` to make the call.
- Any `spec/services/channels/diff_computer_spec.rb` if it exists.

Note: `spec/services/channels/diff_apply_spec.rb` references `title_changed_at`
/ `handle_changed_at` — that is fine, those columns stay; the spec is deleted
because `Channels::DiffApply` is deleted.

### Modify

- `config/routes.rb` — shrink the `:channels` resources block; remove the
  `:edit`, `:update`, `diff`, `apply_diff` actions and the `:preview` nested
  resource. Add the star-only update path. See "Post-cut routes".
- `app/controllers/channels_controller.rb` — remove the `edit`, `update`,
  `diff`, `apply_diff` actions and every private method that exists only to
  serve them. Keep `index`, `show`, `connect_google`, `destroy`, `videos`,
  `panes`, and the sort / filter helpers. See "ChannelsController post-cut
  shape".
- `app/controllers/channels/stars_controller.rb` — **new file** (the star-only
  update path). See "Star-only update path".
- `app/models/channel.rb` — remove the `has_many :channel_diffs` association and
  the `open_channel_diff` method. Remove the model gate methods `title_locked?`,
  `handle_locked?`, `title_unlock_at`, `handle_unlock_at`, and the
  `TITLE_HANDLE_LOCK_WINDOW` constant (they served only the now-deleted edit
  form / diff apply). Keep `before_update :prevent_url_change`, the `star`
  attribute, all validations, `enqueue_initial_sync`, `enqueue_sync_on_star`,
  the friendly-finder, calendar derivation, and the `channel_change_logs`
  association.
- `app/helpers/channels_helper.rb` — remove `title_gate_open?`,
  `handle_gate_open?`, `title_unlock_date`, `handle_unlock_date`, and
  `channel_reminder_name` (all consumed only by the deleted `_form` / controller
  `strip_gated_fields!`). Keep `channel_display_title`, `channel_display_url`,
  `channel_url_label`, `formatted_subscriber_count` and every other display
  helper used by `index` / `show` / `_pane` / `_videos_table`.
- `app/views/channels/show.html.erb` — remove the `[ e ]` edit bracketed-link
  from `:breadcrumb_actions`; remove the empty `channel_diff_banner`
  `turbo_frame_tag` slot and its explanatory comment. Keep `[ changes ]`
  (history), `[ sync ]`, `[ revoke ]`, `[ - ]`. **`[ sync ]` change:** the link
  currently points at `/syncs/channel/:id?intent=diff_check`. After A0 there is
  no diff-check intent for channels — change the href to plain
  `/syncs/channel/:id` (the overwrite intent, which runs `ChannelSync`, the
  one-way cache pull). Keep the `data-keyboard-page-action="sync"` attribute.
- `app/views/channels/_pane.html.erb` — the inline `[star]` / `[unstar]` form
  currently `form_with(model: channel)` POSTs to `channels#update`. Repoint it
  at the new star-only path. See "Star-only update path".
- `app/jobs/channel_sync.rb` — **keep the job**, it is the one-way pull. Verify
  it has no diff-emitting branch: as written it calls `client.fetch_channel` and
  `channel.update!(normalized.merge(...))` — pure cache overwrite, no
  `ChannelDiff` involvement. **No change needed** unless a grep turns up a
  `ChannelDiff` reference inside it (it does not). Leave it untouched.
- `app/controllers/syncs_controller.rb` — remove the `"channel"` entry from
  `DIFF_CHECK_JOBS`. The constant becomes `{ "video" => "VideoDiffCheckJob" }`.
  The `create_diff_check` / `INTENTS` machinery stays for the video surface. A
  channel `[sync]` now only ever runs the `overwrite` intent (`ChannelSync` via
  `BulkSyncJob`), which is correct for a read-only mirror.
- `config/sidekiq_cron.yml` — remove the `channel_diff_check` cron entry (lines
  under the "Phase 7.5 §11i — daily Channel diff check" comment). Leave
  `video_diff_check_bulk` and every other entry.
- `app/services/notification_formatter/templates.rb` — remove the
  `"channel_diff_detected" => ChannelDiffDetected` registry line.
- `app/models/notification.rb` — remove the `channel_diff_detected: 10` enum
  value and its comment block. **Caution:** removing an enum value shifts
  nothing (values are explicit integers, not positional), but confirm no other
  enum value reuses `10`. If any production-shaped seed or fixture references
  `channel_diff_detected`, scrub it.
- `db/schema.rb` / `db/structure.sql` — regenerated by the drop migration
  (`pito-rails` runs `bin/rails db:migrate`); not hand-edited.

### Cross-cutting files to scrub (inbound references)

See the "Removed inbound references checklist" — every link/render of the cut
surface that lives outside `app/views/channels/`.

### Keep (verified read-only / display-only, do not touch)

- `app/views/channels/index.html.erb`, `_picker.html.erb`, `_pane.html.erb`
  (modified for the star path only), `panes.html.erb`, `show.html.erb` (modified
  per above), `_banner.html.erb`, `_links.html.erb`, `_videos_table.html.erb`,
  `_google_panel.html.erb`, `_needs_reauth_banner.html.erb`,
  `_add_pane_dialog.html.erb`, `_revoke_modal.html.erb`,
  `bulk_revokes/show.html.erb`, `analytics/show.html.erb`,
  `_viewer_time_tab.html.erb`, `change_logs/index.html.erb`,
  `change_logs/index.json.jbuilder`.
- `app/controllers/channels/analytics_controller.rb`,
  `analytics_refresh_controller.rb`, `change_logs_controller.rb`,
  `bulk_revokes_controller.rb`.
- `app/controllers/channel_revokes_controller.rb`.
- `app/jobs/channel_sync.rb` (the one-way pull).
- `app/models/channel_change_log.rb`.
- `app/javascript/controllers/file_upload_controller.js` — **KEEP.** It is also
  wired by `app/views/calendar/entries/...` (grep confirmed `file-upload` usage
  outside channels). Only `channel_preview`, `banner_upload`, `links_repeater`,
  and `reminder_link` controllers are channel-edit exclusive and get deleted.
- `app/views/shared/_diff_table.html.erb`, `_wide_modal.html.erb` — **KEEP.**
  Both are shared with the video surface (`videos/diff.html.erb` renders
  `shared/diff_table`; `_wide_modal` is used by games / notes / settings / video
  panes). A0 must not delete them.
- `app/services/youtube/client.rb` — **KEEP the file.** `#update_channel`,
  `#set_watermark`, `#unset_watermark`, `#upload_banner` become unused by Rails
  after A0, but `client.rb` is a single multi-method service still exercised by
  `fetch_channel` (used by `ChannelSync`) and by the video surface. Removing the
  now-dead write methods from `client.rb` is a tidy-up that belongs to a later
  pass, not A0 — **leave `client.rb` untouched** to keep A0's blast radius
  tight. Flag it as a follow-up.

### Decoupling verification (do before deleting)

The implementer runs these greps and acts on the result:

1. `ChannelChangeLog` / `change_logs` — confirmed independent. The controller
   reads `@channel.channel_change_logs`; the view renders `log.field` /
   `log.old_value` / `log.new_value` / `log.changed_by_user`. No `ChannelDiff`,
   no edit-form dependency. **Keep as-is.**
2. Grep `open_channel_diff` repo-wide — every hit must be inside files being
   deleted or inside `channels_controller.rb` (the `diff` / `apply_diff`
   actions, deleted). If a surviving file references it, stop and report.
3. Grep `channel_diffs` repo-wide — same: all hits inside deleted files, the
   migration, the model association line being removed, or schema/structure
   (regenerated).
4. Grep `ChannelDiff` (the constant) repo-wide — confirm no surviving file
   constantizes it.
5. `app/helpers/preview_helper.rb` — grep every method name it defines against
   the surviving view/component set. If all consumers are deleted files, delete
   the helper. Otherwise keep the file and strip only the channel-preview
   methods.
6. Grep `WatermarkPreviewComponent` — confirm `_form.html.erb` is the only
   consumer (it is). Then it is safe to delete the component.
7. Grep `edit_channel_path`, `diff_channel_path`, `apply_diff_channel_path`,
   `channel_preview_path` repo-wide (app + spec) — every hit must be inside a
   deleted file, a rewritten spec, or a file in the "scrub" checklist below. A
   leftover hit is a routing error waiting to 500.

## Post-cut routes

The current `:channels` resources block:

```ruby
resources :channels, only: [ :index, :show, :edit, :update, :destroy ] do
  collection do
    get :panes
    post :connect_google
  end
  member do
    get  :revoke, to: "channel_revokes#show",   as: :revoke
    post :revoke, to: "channel_revokes#create"
    get :videos
    get   :diff
    patch :apply_diff
  end
  resource :analytics, only: :show, controller: "channels/analytics"
  post "analytics/refresh",
       to: "channels/analytics_refresh#create",
       as: :analytics_refresh
  resources :change_logs, only: :index, path: "history",
                          controller: "channels/change_logs"
  resource :preview, only: :show, controller: "channels/previews"
end
```

becomes:

```ruby
resources :channels, only: [ :index, :show, :destroy ] do
  collection do
    get :panes
    # Phase 24 — Google OAuth dance entry point.
    post :connect_google
  end
  member do
    # Phase 24 — per-channel revoke flow.
    get  :revoke, to: "channel_revokes#show",   as: :revoke
    post :revoke, to: "channel_revokes#create"
    # Nested videos endpoint used by the pito CLI.
    get :videos
    # Unit A0 — channel is a read-only mirror. The only mutable
    # channel attribute is `star`; it rides a dedicated singular
    # `star` resource so the general `update` action (which carried
    # the now-removed edit-form fields and the diff surface) is gone
    # entirely. PATCH /channels/:id/star.
    resource :star, only: :update, controller: "channels/stars"
  end
  # Phase 13.3 — per-channel analytics dashboard.
  resource :analytics, only: :show, controller: "channels/analytics"
  post "analytics/refresh",
       to: "channels/analytics_refresh#create",
       as: :analytics_refresh
  # Phase 7.5 §11g — Channel Change History View (read-only audit
  # trail). Kept deliberately as the read-only mirror's history.
  resources :change_logs, only: :index, path: "history",
                          controller: "channels/change_logs"
end
```

Removed: `:edit`, `:update` from the `only:` list; the `get :diff` and
`patch :apply_diff` member routes; the `resource :preview` nested resource.
Added: `resource :star, only: :update`.

The `/channels/revokes/:ids` bulk-revoke routes and the
`get "/settings/youtube"` redirect above the block are untouched.

Named route helper after the change: `channel_star_path(channel)` →
`PATCH /channels/:channel_id/star`. The route helpers `edit_channel_path`,
`diff_channel_path`, `apply_diff_channel_path`, `channel_preview_path` no longer
exist — any leftover reference is a hard failure (covered by the "scrub"
checklist and a routing request spec).

## Star-only update path

The pre-cut design routed the `star` toggle through the general
`channels#update` action, which also carried the edit-form fields and the JSON
CLI path. The cleanest post-cut design is a **dedicated singular `star`
resource** with its own controller — it is unambiguous, it cannot be smuggled
extra fields, and it keeps `ChannelsController` free of any mutation action.

New file `app/controllers/channels/stars_controller.rb`:

```ruby
module Channels
  # Unit A0 — channel is a read-only mirror; `star` is the single
  # mutable channel attribute. This controller owns the only channel
  # write path. PATCH /channels/:channel_id/star.
  #
  # Boundary contract (CLAUDE.md): the `star` value arrives as the
  # string "yes" / "no" — never true/false/0/1. Internal storage is
  # Boolean; conversion happens here. The HTML caller (the inline
  # [star]/[unstar] form on the pane) and the JSON caller (pito CLI)
  # both send `channel[star]` as "yes"/"no".
  class StarsController < ApplicationController
    skip_before_action :verify_authenticity_token,
                        if: -> { request.format.json? }

    def update
      @channel = Channel.friendly.find(params[:channel_id])

      raw = params.dig(:channel, :star)
      unless YesNo.yes_no?(raw)
        message = "star must be 'yes' or 'no' (got #{raw.inspect})"
        respond_to do |format|
          format.html { redirect_to channel_path(@channel), alert: message }
          format.json do
            render json: { errors: [ message ] },
                   status: :unprocessable_content
          end
        end
        return
      end

      if @channel.update(star: YesNo.from_yes_no(raw))
        respond_to do |format|
          format.html do
            redirect_to channel_path(@channel), notice: "channel updated."
          end
          format.json do
            render json: ChannelDecorator.new(@channel).as_detail_json
          end
        end
      else
        respond_to do |format|
          format.html { redirect_to channel_path(@channel), alert: "could not update channel." }
          format.json do
            render json: { errors: @channel.errors.full_messages },
                   status: :unprocessable_content
          end
        end
      end
    end
  end
end
```

Key properties:

- Only `star` is ever assigned. Title / handle / description / banner / avatar /
  keywords / country / language / links / watermark fields can appear in the
  params but are **never read** — they are silently ignored (not 422'd),
  matching the pre-cut JSON path's "ignore everything but star" posture.
- The yes/no string boundary is enforced exactly as the old
  `coerce_update_attrs` / `coerce_yes_no_attrs` did. A non-yes/no value is a 422
  (JSON) / flash-alert redirect (HTML).
- `before_update :prevent_url_change` on the model still fires; the URL is never
  in the param set so it never trips, but the guard stays as defense-in-depth.

View change — `app/views/channels/_pane.html.erb`, the inline star form.
Current:

```erb
<%= form_with(model: channel, html: { style: "display: inline; ..." }) do |f| %>
  <%= f.hidden_field :star, value: channel.star? ? "no" : "yes" %>
  <button type="submit" class="bracketed" ...>[<%= channel.star? ? "unstar" : "star" %>]</button>
<% end %>
```

Repoint to the star resource:

```erb
<%= form_with(url: channel_star_path(channel), method: :patch,
              html: { style: "display: inline; margin-left: 8px;" }) do |f| %>
  <input type="hidden" name="channel[star]"
         value="<%= channel.star? ? "no" : "yes" %>">
  <button type="submit" class="bracketed"
          style="background: none; border: none; cursor: pointer; padding: 0; color: inherit; font: inherit;">
    [<%= channel.star? ? "unstar" : "star" %>]
  </button>
<% end %>
```

The param shape stays `channel[star]="yes"|"no"` so the CLI's existing
`update_channel_body` (`{ "channel": { "star": "yes" } }`) decodes unchanged
against the new endpoint — but note the CLI still PATCHes `/channels/:id.json`,
not `/channels/:id/star.json`. See "Cross-stack scope" — the CLI URL change is a
deferred item, not part of A0; the JSON `update` action being removed means the
CLI's channel star toggle would break on a real server. Because the TUI / CLI
surface is paused (per the roadmap and auto-memory), this is acceptable: it is
recorded as a deferred cross-surface consequence. A0 does not keep a
compatibility shim alive for a paused surface. See "Open questions" Q1.

## Drop migration outline

`pito-rails` authors a new timestamped migration, e.g.
`db/migrate/<ts>_drop_channel_diffs.rb`:

- `drop_table :channel_diffs` — the table carried `channel_id`, `detected_at`,
  `resolved_at`, `field_diffs` (jsonb), `resolution_payload` (jsonb),
  `resolved_by_user_id`, timestamps; four indexes (including the partial unique
  `index_channel_diffs_open_per_channel`); two foreign keys (`channels` ON
  DELETE CASCADE, `users` ON DELETE NULLIFY).
- Provide a reversible `change` using `drop_table` with a block that re-creates
  the original schema (mirror `20260511024709_create_channel_diffs.rb` exactly:
  same columns, same indexes, same FKs) so `db:rollback` works. If a faithful
  reversible block is impractical, use `def up` / `def down` with `down` raising
  `ActiveRecord::IrreversibleMigration` — but reversible is preferred and is
  straightforward here since the original migration is small.
- Run `bin/rails db:migrate` to regenerate `db/schema.rb` and
  `db/structure.sql`. Both are committed as part of the same change.
- The `add_channel_resource_fields` columns (`title_changed_at`,
  `handle_changed_at`, watermark columns, `keywords`, `country`,
  `default_language`, `links`) are **not** dropped — see "Scope boundaries" and
  "Open questions" Q2.

## ChannelsController post-cut shape

Keep: `index`, `show`, `connect_google`, `destroy`, `videos`, `panes`, and the
private helpers `max_panes`, `pane_title_length`, `filter_on?`,
`active_filters`, `sanitized_sort_key`, `sanitized_dir`, `sort_clause`, plus the
`ALLOWED_SORTS` / `ALLOWED_DIRS` / `DEFAULT_SORT` / `DEFAULT_DIR` constants and
the `include FriendlyRedirect` / `include YoutubeConnectionOauthRedirect` lines.

In `show`, the `@youtube_connection` assignment and the videos-aggregate query
stay. The `skip_before_action :verify_authenticity_token` line stays (the
`index` / `show` / `videos` JSON branches still need it).

Remove the actions: `edit`, `update`, `diff`, `apply_diff`.

Remove every private method that exists only to serve those actions:
`star_only_html_request?`, `perform_star_toggle_html`, `update_via_json`,
`perform_local_only_update`, `perform_youtube_update`,
`handle_watermark_unset!`, `handle_watermark_set!`, `watermark_upload_present?`,
`banner_upload_present?`, `handle_banner_upload!`, `banner_upload_only?`,
`strip_gated_fields!`, `channel_form_fields_blank?`, `channel_edit_attrs`,
`normalize_links_attributes`, `coerce_update_attrs`, `coerce_yes_no_attrs`,
`extract_diff_decisions_param`, `build_diff_apply_success_message`,
`diff_detail_json`, and the `PERMITTED_EDIT_KEYS` constant.

`coerce_yes_no_attrs` / `YesNo` usage moves to `Channels::StarsController`
(re-implemented inline there as shown above — do not leave a shared private
method behind in `ChannelsController`).

After the cut, `ChannelsController` has no write action at all; the only channel
mutation in the app is `Channels::StarsController#update` and
`ChannelsController#destroy`.

## Removed inbound references checklist

Every one of these must be scrubbed; a leftover is a 500 or a dead link:

- [ ] `app/views/channels/show.html.erb` — remove the `[ e ]`
      (`edit_channel_path`) bracketed-link in `:breadcrumb_actions`.
- [ ] `app/views/channels/show.html.erb` — remove the
      `turbo_frame_tag "channel_diff_banner"` slot and its comment block.
- [ ] `app/views/channels/show.html.erb` — change the `[ sync ]` href from
      `/syncs/channel/:id?intent=diff_check` to `/syncs/channel/:id`.
- [ ] `app/views/channels/_pane.html.erb` — repoint the star form to
      `channel_star_path` (see "Star-only update path").
- [ ] `app/controllers/syncs_controller.rb` — drop `"channel"` from
      `DIFF_CHECK_JOBS`.
- [ ] `app/services/notification_formatter/templates.rb` — drop the
      `channel_diff_detected` registry line.
- [ ] `app/models/notification.rb` — drop the `channel_diff_detected` enum
      value + comment.
- [ ] `config/sidekiq_cron.yml` — drop the `channel_diff_check` entry.
- [ ] Grep `edit_channel_path` repo-wide — scrub every app hit. Known:
      `channels/show.html.erb`. Confirm none in nav, breadcrumbs,
      `_pane.html.erb`, `_picker.html.erb`, `index.html.erb`, or any shared
      partial.
- [ ] Grep `diff_channel_path` / `apply_diff_channel_path` — known hits in
      `_open_diff_banner.html.erb` and `diff.html.erb` (both deleted) and
      `channel_diff_check_job.rb` (deleted). Confirm no survivor.
- [ ] Grep `channel_preview_path` — known hits in `edit.html.erb` /
      `_form.html.erb` (deleted) and `previews_controller.rb` (deleted). Confirm
      no survivor.
- [ ] Grep `ChannelPreviewComponent` / `WatermarkPreviewComponent` — confirm no
      survivor outside deleted files.
- [ ] Grep `"/channels/" .* "/diff"` style hardcoded strings — the
      `channel_diff_detected` notification template (deleted) and
      `channel_diff_check_job.rb` (deleted) build `/channels/:slug/diff` URLs.
      Confirm no survivor builds that path.
- [ ] Grep `intent=diff_check` — known hit `channels/show.html.erb` (changed
      above). Confirm the only remaining `diff_check` references are the video
      surface (`syncs_controller.rb` video branch, `videos/show.html.erb`).
- [ ] `docs/` references — `docs/architecture.md` channel section and
      `docs/mcp.md` (the `channel_diff_*` tools) describe the now-cut surface.
      **A0 does not edit `docs/` (out of `pito-rails` scope and out of
      architect-spec write scope).** Flag for the docs pass: the architecture
      channel section needs a read-only-mirror rewrite and `docs/mcp.md` needs a
      deferred-cut note on the channel diff tools.

## Regression spec list

Per the roadmap's regression-spec mandate, `pito-rails` ships these in the same
commit. Every layer touched carries its specs; additive, not substitutive. The
full suite green is the exit gate.

### Routing / controller — request specs

- `spec/requests/channels/star_spec.rb` — **new.** The surviving star-only write
  path:
  - `PATCH /channels/:id/star` with `channel[star]=yes` stars an unstarred
    channel; response redirects to the show page (HTML) with the "channel
    updated." notice; `channel.reload.star` is `true`.
  - `PATCH .../star` with `channel[star]=no` unstars a starred channel.
  - `PATCH .../star.json` with `channel[star]=yes` returns the channel detail
    JSON; `star` toggled.
  - `PATCH .../star` with `channel[star]=true` (bad boundary value) is a
    flash-alert redirect (HTML) / `422` with an `errors` array (JSON); `star`
    unchanged.
  - `PATCH .../star` with `channel[star]=yes` AND `channel[title]="hacked"` AND
    `channel[description]="x"` — `star` toggles, `title` and `description` are
    **unchanged** (the removed attributes are ignored, not assigned). This is
    the "read-only mirror" proof at the controller layer.
  - `PATCH .../star` resolves by friendly slug and by integer id.
- `spec/requests/channels/read_only_routes_spec.rb` — **new.** Asserts the
  removed routes are gone:
  - `GET /channels/:id/edit` is not routable —
    `expect { get "/channels/#{c.to_param}/edit" }.to raise_error(ActionController::RoutingError)`
    (or the request returns `404`, depending on the test harness' routing-error
    handling — match the project's existing convention for "route does not
    exist" assertions; check an existing not-routable spec for the idiom).
  - `PATCH /channels/:id` (the old general update) is not routable.
  - `GET /channels/:id/diff` is not routable.
  - `PATCH /channels/:id/apply_diff` is not routable.
  - `GET /channels/:id/preview` is not routable.
  - `Rails.application.routes.url_helpers` does not respond to
    `edit_channel_path` / `diff_channel_path` / `apply_diff_channel_path` /
    `channel_preview_path` (guards against a stray helper reference).
  - The surviving routes still resolve: `GET /channels`, `GET /channels/:id`,
    `GET /channels/:id/history`, `GET /channels/:id/videos`,
    `PATCH /channels/:id/star`, `GET /channels/:id/revoke`.
- Update `spec/requests/channels_show_spec.rb` — remove the example
  `"exposes the empty channel_diff_banner Turbo frame slot"` (the slot is gone)
  and rewrite the `[ sync ]` example: it currently asserts the body includes
  `/syncs/channel/:id?intent=diff_check`; change it to assert the body includes
  `/syncs/channel/:id` and does **not** include `intent=diff_check`. Add an
  example asserting the show page does **not** render an `edit_channel_path`
  link / `[ e ]` action.
- Update `spec/requests/channels_spec.rb` if any example references the edit /
  update / diff / preview routes (the grep in "Decoupling verification" item 7
  finds them). The index-table examples that only touch sort / filter / columns
  are unaffected.

### View — system specs

- `spec/system/channel_show_journey_spec.rb` (existing) — update: assert the
  channel show page renders read-only — no `[ e ]` / `[ edit ]` affordance, no
  diff banner, no `[ review changes ]` link. Keep / extend the existing coverage
  of the `[ changes ]` history link, `[ sync ]`, `[ revoke ]`, the analytics
  pane, the Google panel, the videos table.
- `spec/system/channels/read_only_channel_spec.rb` — **new** (or fold into the
  journey spec if the project prefers fewer system files — match the existing
  channel system-spec granularity). Asserts:
  - Visiting `/channels/:id/edit` does not render an edit form (404 / not
    routable — assert via the project's convention).
  - The channel show page has no edit affordance and no diff banner.
  - The `[star]` / `[unstar]` toggle on a channel pane still works end-to-end:
    starring a channel from the pane flips the label and persists (this
    exercises the new `channel_star_path` form).
- Delete the system specs listed under "Specs to delete": the channel edit form,
  banner upload, watermark preview, channel preview, diff resolution, and
  (conditionally) the calendar reminder spec.

### Model / migration

- `spec/models/channel_spec.rb` — update: remove every example covering
  `open_channel_diff`, the `channel_diffs` association, and the `title_locked?`
  / `handle_locked?` / `title_unlock_at` / `handle_unlock_at` gate methods. Add
  an example asserting `Channel.new` does **not** respond to `open_channel_diff`
  and that `Channel.reflect_on_association(:channel_diffs)` is `nil`. Keep every
  validation / friendly-finder / calendar-derivation / star-callback example.
- `spec/migrations/drop_channel_diffs_spec.rb` — **new** (mirror the existing
  `spec/migrations/add_channel_resource_fields_spec.rb` idiom). Asserts that
  after migration `ActiveRecord::Base.connection.table_exists?(:channel_diffs)`
  is `false`. If the project's migration-spec convention instead asserts against
  `db/schema.rb` content or runs the migration up/down, follow that convention.
- `spec/models/channel_diff_spec.rb` — deleted (model gone).

### Component specs

- `spec/components/channel_preview_component_spec.rb` — deleted.
- `spec/components/watermark_preview_component_spec.rb` — deleted.
- Surviving channel-adjacent components (e.g.
  `Imports::ProgressIndicatorComponent`, `BracketedLinkComponent`,
  `SortableHeaderComponent`) keep their existing specs untouched — A0 does not
  touch them.

### Helper / job / service

- `spec/helpers/channels_helper_spec.rb` — update: remove the examples for
  `title_gate_open?`, `handle_gate_open?`, `title_unlock_date`,
  `handle_unlock_date`, `channel_reminder_name`. Keep the display-helper
  examples.
- `spec/jobs/channel_sync_spec.rb` — **keep, verify green.** `ChannelSync` is
  untouched; its spec must still pass and proves the one-way pull survives.
- `spec/jobs/channel_diff_check_job_spec.rb` — deleted (job gone).
- `spec/services/channels/diff_apply_spec.rb`, `diff_persister_spec.rb`,
  `diff_computer_spec.rb` (if present) — deleted (services gone).
- `spec/requests/syncs_diff_check_spec.rb` — update: this spec covers both
  channel and video diff-check intents. Remove the channel-intent examples (a
  channel `[sync]` no longer enqueues `ChannelDiffCheckJob`); if the channel
  branch is exercised, instead assert a channel sync now runs the overwrite
  path. Keep the video-intent examples. If the spec is channel-only, delete it;
  if mixed, trim it.
- Notification specs — grep `channel_diff_detected` under `spec/` and scrub any
  example that creates a notification with that kind. The
  `notification_formatter` spec set: remove the `ChannelDiffDetected` template
  example.

### Exit gate

`bundle exec rspec` is fully green and `bundle exec rubocop` is clean before
`pito-rails` reports back. The master agent commits only after the user
validates the manual recipe.

## Manual test recipe

Fresh terminal, `bin/dev` running, logged in.

1. **Edit route is gone.** Open `http://localhost:3000/channels`, click a
   channel to reach `/channels/:slug`. Confirm there is **no `[ e ]` /
   `[ edit ]`** link in the heading-actions row — only `[ changes ]`,
   `[ sync ]`, `[ revoke ]`, `[ - ]`.
2. Manually visit `http://localhost:3000/channels/<slug>/edit`. Expect a routing
   error / 404 page — not an edit form.
3. Manually visit `http://localhost:3000/channels/<slug>/diff` and
   `http://localhost:3000/channels/<slug>/preview`. Both expect a routing error
   / 404 — not a diff page, not a preview.
4. **No diff banner.** On the channel show page, confirm there is no "youtube
   has N newer values" banner and no empty diff-banner frame in the page source
   (view-source, search `channel_diff_banner` — absent).
5. **Star still toggles.** On `/channels` open two or more channels in
   split-view panes (select rows, `[ open N ]`). In a pane, click `[star]` — the
   label flips to `[unstar]`, the page reloads, the channel show reflects the
   new star state. Click `[unstar]` to flip back. Reload the page; the state
   persisted.
6. **Star via curl (JSON path).** With a channel id `N`:
   ```
   curl -X PATCH http://localhost:3000/channels/N/star.json \
     -H "Content-Type: application/json" \
     -d '{"channel":{"star":"yes"}}'
   ```
   Expect a `200` with the channel detail JSON, `"star"` reflecting the toggle.
   Then send `{"channel":{"star":"bad"}}` — expect `422` with an `errors` array.
   Then send `{"channel":{"star":"yes","title":"HACKED"}}` — expect `200`, and
   confirm on the show page the title is **unchanged** (the removed field was
   ignored).
7. **Sync still pulls.** On the channel show page click `[ sync ]`. Confirm it
   routes to the sync confirmation screen (`/syncs/channel/:id`) and, on
   confirm, enqueues the one-way `ChannelSync` (check `/sidekiq` for the job, or
   confirm `last_synced_at` updates). There is no diff-check, no diff banner
   appears afterward.
8. **History survives.** Click `[ changes ]` — `/channels/:slug/history` renders
   the read-only change-history table (or the "no changes yet." empty state).
   This surface is untouched.
9. **Cron is gone.** `grep channel_diff_check config/sidekiq_cron.yml` — no
   match. `video_diff_check_bulk` is still present.

Teardown: none required — the star toggles and the sync are idempotent; re-star
/ re-sync to restore prior state if desired.

## Cross-stack scope

- **Rails web app** — in scope. The full A0 cut, as specified above.
- **`pito` CLI / TUI (`extras/cli/`)** — **nothing to cut; skip the `pito-rust`
  dispatch.** Investigation findings:
  - The TUI has **no channel edit screen** —
    `extras/cli/src/ui/channel_detail.rs` renders a read-only KV view + video
    table; grep for `diff` / `edit` / `PATCH` in it returns nothing.
  - The TUI has **no channel diff / reconcile view** anywhere.
  - The CLI's `ApiClient::update_channel` is **already star-only**: its
    signature is `update_channel(&self, id: u64, star: Option<bool>)` and its
    wire body (`HttpClient::update_channel_body`) is
    `{ "channel": { "star": "yes"|"no" } }` — no title / handle / description /
    banner fields are sendable. There is no channel attribute-write surface to
    remove.
  - Consequence — the CLI's `update_channel` PATCHes `/channels/:id.json` (the
    general update action), which A0 **removes**. Against a real post-A0 server
    the CLI star toggle would 404. This is a **deferred cross-surface
    consequence**, not part of A0: the TUI / CLI surface is paused for the whole
    beta-2 wave (roadmap "Surface pause status" + auto-memory). When the pause
    lifts, the CLI's channel star endpoint gets repointed at
    `/channels/:id/star.json` under its own architect spec. A0 deliberately does
    **not** keep a compatibility shim on the `channels#update` action alive to
    serve a paused surface.
- **MCP (`app/mcp/`)** — **not touched.** Deferred-cut items recorded in the
  roadmap scope amendment: `channel_diff_show` and `channel_diff_apply`
  (`app/mcp/tools/channel_diff_show.rb`, `channel_diff_apply.rb`) go dead
  because `ChannelDiff` is gone, and a future `update_channel` MCP tool shrinks
  to star-only. A0 leaves all MCP code and `spec/mcp/` untouched. **Caveat for
  the implementer:** the MCP tool specs
  `spec/mcp/tools/channel_diff_show_spec.rb` and `channel_diff_apply_spec.rb`
  exercise tools that depend on the `ChannelDiff` model and the `channel_diffs`
  table — once the table is dropped these specs will fail. Because MCP is
  paused, the resolution is: **delete `spec/mcp/tools/channel_diff_show_spec.rb`
  and `spec/mcp/tools/channel_diff_apply_spec.rb` AND
  `app/mcp/tools/channel_diff_show.rb` and `channel_diff_apply.rb`** as part of
  A0 — they are unconditionally dead once `ChannelDiff` is gone and leaving them
  would red the suite. This is the one narrow MCP exception, and it is
  removal-only (no behavior change to live MCP tools). The MCP tool registry
  must also be scrubbed of these two tool registrations — grep `channel_diff`
  under `app/mcp/` and remove the registry entries so the catalog does not
  reference deleted classes. Note this back to the master agent so the
  MCP-unpause spec knows the diff tools are already physically gone, not just
  deferred.
- **Cloudflare website (`extras/website/`)** — not in scope; no channel surface
  there.

## Open questions

Q1 — **CLI star endpoint break.** A0 removes `channels#update`, which the paused
`pito` CLI still PATCHes for its star toggle. The spec's position is: do **not**
keep a shim — the surface is paused, the break is a recorded deferred item, and
a shim would leave dead edit-form-shaped plumbing on `ChannelsController` purely
for a surface no one is running. If the master agent disagrees and wants the
JSON star path preserved on `channels#update` as a thin compatibility action
until the CLI is repointed, that is a one-line `only: [..., :update]` re-add
plus a star-only JSON `update` action — flag it and the spec adjusts. Default:
no shim.

Q2 — **Edit-form-only DB columns.** `title_changed_at`, `handle_changed_at`,
`watermark_url`, `watermark_timing`, `watermark_offset_ms`, `keywords`,
`country`, `default_language`, `links` were added for the now-cut edit form. A0
keeps them (only `channel_diffs` is dropped) to keep the migration surface tight
and because `ChannelSync#fetch_channel` may still cache a subset of them. If the
master agent wants these columns dropped as part of the read-only conversion,
that is a separate, larger drop migration with its own schema-spec impact —
recommend it as a follow-up unit (A-channels polish or a dedicated cleanup), not
A0. Default: keep the columns, drop only the table.

Q3 — **`calendar_reminder_spec.rb` scope.** The spec is listed for conditional
delete-or-trim. If it turns out to exercise a calendar reminder surface that has
nothing to do with the channel edit form, the implementer trims rather than
deletes. The spec instructs the implementer to make this call from a grep; flag
back if the result is ambiguous.
