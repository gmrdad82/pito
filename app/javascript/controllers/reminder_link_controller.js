import { Controller } from "@hotwired/stimulus"

// Phase 7.5 §11c — `[remind me on YYYY-MM-DD]` link stub.
//
// This controller intercepts the click on the bracketed link
// rendered next to the 14-day gate message in the channel edit
// form. It captures the link's data values (unlock date, field
// name, channel id) and prevents the default navigation.
//
// The POST → /calendar/entries.json + toast rendering is owned
// by sub-spec 11h, which extends this stub. 11c ships the stub so
// the form renders and the click is a no-op rather than a 404.
// When 11h lands, the `create` action is fleshed out and the toast
// target inside the form's lead-paragraph area is populated.
//
// Strict no `confirm()` / `alert()` / `prompt()` per CLAUDE.md hard rule.
export default class extends Controller {
  static values = {
    unlockDate: String,
    field: String,
    channelId: Number
  }
  static targets = ["toast"]

  create(event) {
    event.preventDefault()
    // Phase 7.5 §11h fills this in:
    //   1. POST /calendar/entries.json with the prefilled body
    //      ({ kind: "reminder", title: "Channel <field> unlock — <name>",
    //        starts_at: this.unlockDateValue, all_day: true,
    //        channel_id: this.channelIdValue }).
    //   2. On 201, render a toast into the form's #toast container
    //      saying "reminder created for <unlock date>."
    //   3. On error, render a toast saying "could not create reminder."
    //
    // Until 11h lands, this stub is intentionally a no-op (silent
    // click capture) so the user does not navigate away from the
    // form.
  }
}
