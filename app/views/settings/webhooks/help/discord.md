# Discord webhook setup

This guide walks you, step by step, from never having made a Discord
webhook to receiving a pito test ping in your Discord channel. No
prior Discord-admin experience needed — if you can open Discord and
see a channel's gear icon, you can follow this.

A Discord webhook is just a URL: when something sends an HTTP POST
to that URL, Discord writes the request body as a message in the
channel you picked. Pito uses this to deliver notifications.

Before you start: you need the `Manage Webhooks` permission on the
channel you'll target. On a Discord server you own, this is automatic.
On a server you're a member of, ask the owner or an admin to grant
the role — without it the menu in Step 2 won't appear.

## Step 1 — Open the channel settings

Open Discord (desktop, browser, or mobile — all three work). Navigate
to the server, then to the specific channel where pito notifications
should land.

Hover over the channel name in the channel list. A small gear icon
appears next to it. Click the gear to open `Channel Settings`.

(Alternative path: right-click the channel → `Edit Channel`. Same
destination.)

## Step 2 — Create a webhook

In the left sidebar of the Channel Settings panel, click
`Integrations`.

The Integrations page lists what's already wired up (often empty on
a fresh server). Find the `Webhooks` section and click it. If a
webhook already exists, you'll see a list; otherwise the page shows
a `Create Webhook` button.

Click `New Webhook` (or `Create Webhook` if this is the first one).
Discord drops a freshly-created webhook into the list, named
something like "Captain Hook" with the default Discord avatar.

Expand the new entry. The form has:

- Name — change it to `pito` (or any name you'll recognise later).
- Channel — should default to the channel you opened. Leave it,
  or pick a different one in the same server.
- Avatar — optional; click the avatar to upload a custom image.

Click `Copy Webhook URL` at the bottom of the form. The URL looks
like:

    https://discord.com/api/webhooks/1234567890123456789/aBcDeF-GhIjKl_MnOpQr-StUvWx-YzAbCdEfGh

Click `Save Changes` to persist the webhook in Discord. (Discord
sometimes lets you copy the URL before saving — copy after saving so
the webhook actually exists when pito tests it.)

## Step 3 — Paste into Pito

Switch back to pito. On the Settings page, find the Discord pane.
Paste the URL into the `webhook URL` field.

Click `[update]`.

Pito does two things:

1. Validates the URL shape — it must start with
   `https://discord.com/api/webhooks/` (or `https://discordapp.com/api/webhooks/`
   — both Discord host names are accepted) and carry the
   numeric-id + token segments shown above.
2. Sends a test message to the channel. Only if Discord accepts the
   message does pito save the URL.

Within a second, the Discord channel should show a message that
reads:

    pito test ping — Discord webhook configured.

That's it. You're done.

## Notifications behavior

Two checkboxes live below the URL field:

- `deliver every notification` — pito posts to Discord every time it
  generates a notification (channel sync diffs, video import results,
  scheduled-publish reminders, etc.).
- `daily digest` — pito posts a single roll-up message at 09:00 in
  your configured time zone, summarising the previous 24 hours.

The two toggles work independently. Turn one on, both on, or
neither. Both off means the URL is saved but pito stays quiet —
handy if you want to wire the integration up first and switch it on
later.

## Troubleshooting

**"webhook URL is invalid"** — the URL shape doesn't match. Discord
webhook URLs always start with `https://discord.com/api/webhooks/`
or `https://discordapp.com/api/webhooks/` and have two slash-
separated segments after `webhooks/`: a numeric id and a token.
Re-copy the URL from Discord and try again. Stray whitespace before
or after the URL is stripped automatically.

**"test ping failed: Discord returned 404"** — the webhook was
deleted in Discord (someone clicked the trash icon in the Webhooks
list, or removed the entire integration). Re-run Step 2 to create a
fresh URL and paste the new one.

**"test ping failed: Discord returned 401"** — the token portion of
the URL is wrong, or the webhook was reset. Re-run Step 2 and copy
the URL fresh.

**"can't see the Integrations menu"** — you don't have the
`Manage Webhooks` permission on this channel (or anywhere on the
server). Ask the server owner or an admin to grant you the role,
then re-open the channel settings.

**"test ping failed: connection timed out"** — pito couldn't reach
`discord.com`. Usually a network blip; try again in a moment. If it
persists, check that outbound HTTPS to `discord.com` is allowed
from the host running pito.

**The channel disappeared** — if the Discord channel was deleted
after you saved the URL, the next pito delivery attempt will fail.
Re-run Step 2 against a different channel (in the same or another
server) and paste the new URL into the Discord pane.

**Need to start over** — clear the `webhook URL` field and click
`[update]`. Pito removes the saved configuration. Both toggles reset
to off automatically.
