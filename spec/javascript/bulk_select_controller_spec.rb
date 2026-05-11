require "rails_helper"

# 2026-05-11 — regression guard for the channels (and projects /
# videos / notifications) bulk-open `Content missing` fix. The bulk-select
# Stimulus controller injects `[open N]` / `[sync N]` / `[delete N]` /
# `[revoke N]` anchors at runtime. When the surrounding context is a
# `<turbo-frame>` (e.g. `channels-index-table`), Turbo scopes the click
# to that frame; the panes / deletions / syncs full-page responses
# don't carry that frame id and Turbo errors with "Content missing".
#
# The fix sets `data-turbo-frame="_top"` directly on each injected anchor
# so the click escapes the frame regardless of any cascade behavior from
# the parent container. This spec asserts the controller source carries
# that `setAttribute` call for every injected action.
RSpec.describe "bulk_select_controller.js" do
  let(:controller_source) do
    File.read(Rails.root.join("app/javascript/controllers/bulk_select_controller.js"))
  end

  it "sets data-turbo-frame=_top on the injected [open N] anchor" do
    # The openAction branch hands off to `_setBracketedLink` and passes
    # `_top` as the explicit turbo-frame argument.
    expect(controller_source).to match(
      /_setBracketedLink\(this\.openActionTarget,\s*panesUrl,\s*`open\s+\$\{count\}`,\s*"bracketed",\s*"_top"\s*\)/
    )
  end

  it "sets data-turbo-frame=_top on the injected [delete N] anchor" do
    # The deleteAction branch builds the anchor inline. Look for the
    # setAttribute call inside the `hasDeleteActionTarget` block.
    delete_block = controller_source[/if \(this\.hasDeleteActionTarget\)\s*\{.+?\}\s*\}/m].to_s
    expect(delete_block).to include('setAttribute("data-turbo-frame", "_top")'),
      "expected the [delete N] anchor branch to setAttribute data-turbo-frame=_top"
  end

  it "sets data-turbo-frame=_top on the injected [sync N] anchor" do
    sync_block = controller_source[/if \(this\.hasSyncActionTarget\)\s*\{.+?\}\s*\}/m].to_s
    expect(sync_block).to include('setAttribute("data-turbo-frame", "_top")'),
      "expected the [sync N] anchor branch to setAttribute data-turbo-frame=_top"
  end

  it "sets data-turbo-frame=_top on the injected [revoke N] anchor" do
    revoke_block = controller_source[/if \(this\.hasRevokeActionTarget\)\s*\{.+?\}\s*\}/m].to_s
    expect(revoke_block).to include('setAttribute("data-turbo-frame", "_top")'),
      "expected the [revoke N] anchor branch to setAttribute data-turbo-frame=_top"
  end

  it "_setBracketedLink helper accepts and applies a turboFrame argument" do
    helper_block = controller_source[/_setBracketedLink\(el,[^)]*\)\s*\{.+?\n\s{2}\}/m].to_s
    expect(helper_block).to include('setAttribute("data-turbo-frame", turboFrame)'),
      "expected _setBracketedLink to forward its turboFrame argument onto the injected anchor"
  end
end
