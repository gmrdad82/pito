## step 1 — channel settings

Hover the target channel in the channel list, click the gear icon (or
right-click → `Edit Channel`).

---

## step 2 — create the webhook

`Integrations` → `Webhooks` → `New Webhook`.

Expand the entry, rename to `pito` (or any label), confirm the channel,
optionally upload an avatar. Click `Save Changes`, then `Copy Webhook URL`.

URL shape:

    https://discord.com/api/webhooks/123456789/aBcDeF-GhIjKl

Copy after saving so the webhook exists when pito tests it.

---

## step 3 — paste into pito

Settings → Discord pane. Paste into `webhook URL`, click `[update]`.

Pito validates the URL shape (`https://discord.com/api/webhooks/` or
`https://discordapp.com/api/webhooks/`, numeric id + token) and sends a test
ping. The URL is saved only if Discord accepts it.

You should see in the channel within ~1s:

    pito test ping — Discord webhook configured.

---

## troubleshooting

| Error                | Fix                                      |
| -------------------- | ---------------------------------------- |
| URL invalid          | re-copy from Discord                     |
| test ping 404        | webhook deleted — redo step 2            |
| test ping 401        | token reset — redo step 2                |
| connection timed out | network / `discord.com` reachability     |
| no Integrations menu | missing `Manage Webhooks` on the channel |
| channel disappeared  | channel deleted — redo step 2 elsewhere  |

To reset: clear the `webhook URL` field and `[update]`. Toggles reset to off.
