# pito-cli capture rig

Regenerates the three terminal-cast GIFs (+ `.txt` final-frame transcripts)
that show the `pito-cli` install / manage / update flows. Fully mocked and
**safe to run any time** — see "Why it's safe" below.

## Regenerate

    bash capture.sh

Casts `~/Dev/pito` by default; point at a different checkout with `REPO=`:

    REPO=/path/to/pito bash capture.sh

Output lands in `out/`:

- `pito-install-cast.{gif,txt}` — the installer end to end (version picker,
  host prompt, secrets, stack boot, TOTP enrollment, PATH link, final banner)
- `pito-cli-cast.{gif,txt}` — `pito-cli --help` / `version` / `logs` / `up -d`,
  run bare (as if linked onto PATH by the installer)
- `pito-update-cast.{gif,txt}` — `pito-cli update`'s version picker + the
  zero-downtime blue/green flip

Requires [vhs](https://github.com/charmbracelet/vhs) v0.11+ on `PATH`. The
tapes record at a tall fixed canvas (a workaround for a vhs/xterm.js
rendering stall — see the tapes' SAFETY comment); if ImageMagick's `magick`
is also on `PATH`, `capture.sh` tightens each GIF to its actual content
height afterwards (cosmetic only — skipped with a notice otherwise).

## Why it's safe

Every run is fully mocked — nothing here ever touches a real Docker daemon,
the real network, or the real system:

- **`fakebin/docker`** is a pure no-op: never execs a real `docker`, just
  pattern-matches the handful of `docker` / `docker compose` shapes the
  installer/CLI use and prints realistic-looking output.
- **`DOCKER_HOST=tcp://127.0.0.1:1`** is exported as a second, independent
  guard — even if something slipped past the `PATH` shadowing, this host
  refuses the connection instantly.
- **`fakebin/curl`** never touches the network. It serves the repo's own
  `docker-compose.yml` / `bin/pito-cli` / `bin/pito` / `Caddyfile.lb` /
  `script/update.sh` / `script/deploy-flip.sh` from a local, read-only copy
  (`capture.sh` stages one fresh from `$REPO` on every run — never written
  back) for matching `raw.githubusercontent.com` paths, answers the GitHub
  releases API with 5 canned version tags, answers deploy-flip's localhost
  health probe as instantly healthy, and silently no-ops every other URL.
- **`fakebin/sudo`** and **`fakebin/readlink`** are no-op successes: `sudo`
  exits 0 without ever exec'ing its arguments (so `sudo ln -sf .../pito-cli
  /usr/local/bin/pito-cli` "succeeds" from the installer's point of view —
  no real symlink is ever created); `readlink` answers the two
  `/usr/local/bin` probes as if that symlink already exists (pointing back
  at the sandbox), so `pito-cli update`'s re-link check is silently
  satisfied instead of leaking a temp path into the transcript. Neither
  ever touches the real filesystem outside the run's own sandbox.
- Every run happens inside a fresh `mktemp -d` sandbox that's deleted
  (`trap ... EXIT`) the moment `capture.sh` exits — success, failure, or
  interrupt.

No systemd unit, no Cloudflare tunnel, no real credentials, no real backup
timer, no real PATH symlink, no real image pull — ever.

## Files

- `capture.sh` — the runner described above.
- `pito-install-cast.tape` / `pito-cli-cast.tape` / `pito-update-cast.tape` —
  the three [VHS](https://github.com/charmbracelet/vhs) tapes. Parameterized
  on `${CAST_DIR}` (the sandbox `capture.sh` exports before invoking `vhs`,
  inherited by VHS's recorded shell like any other environment variable) —
  no hardcoded paths, so they run from any checkout via `capture.sh`.
- `fakebin/` — the four mocks described above (`docker`, `curl`, `sudo`,
  `readlink`).
