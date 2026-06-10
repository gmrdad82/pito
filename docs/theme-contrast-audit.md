# Theme contrast audit (WCAG 2.x) — scoped to real token usage

> Branch `theme-contrast-audit`. Reproduce: `bundle exec rails runner script/theme_contrast_audit.rb`.

## Scope (what's actually used where)

- **Text** uses only the `fg` trio (`fg_default`, `fg_dim`, `fg_faded`) plus accents
  **yellow / cyan / orange**, always on **page** (`bg_root`) or **surface**
  (`bg_surface`). Those are the pairs evaluated, at the **AA 4.5:1** text bar
  (`fg_faded` is a placeholder/disabled tone — judged at the 3:1 floor).
  *(`red`/`green`/`purple` have a handful of text uses too but are out of the
  stated scope; they pattern with the other accents — bright = fine on dark, fails
  on light.)*
- **`brand_pito` (`#5170ff`)** is **not text**: it's the ascii **logo blocks**
  (`██████`, on the full-viewport **page**) and the **chatbox / echo borderline**.
  Non-text/UI bar is **3:1** (WCAG 1.4.11).

Contrast = WCAG relative-luminance ratio. ✅ ≥4.5 · ⚠️ 3–4.5 · ❌ <3.

## Findings

### brand_pito (logo + border) — essentially fine
- **vs page: ≥3:1 on every theme** (lowest nord 3.04). The **logo is clear everywhere.**
- As a **border on surface** it dips below 3:1 on only **5 themes** (still 2.4–3.0, never
  invisible): `nord` 2.45, `catppuccin-latte` 2.66, `gruvbox-dark` 2.82, `dracula` 2.92,
  `gruvbox-light` 2.99. Anchor: Tokyo Night (the default) sits at page 4.16 / surface 3.79.
- **Adaptive rule (your proposal):** keep `#5170ff` wherever it ≥ Tokyo Night's level;
  nudge only those 5 (lighten on dark / darken on the 2 light) back to ~3:1+ on surface.
  This is polish, not a bug.

### Dark themes — largely fine
The bright `yellow`/`cyan`/`orange` contrast strongly on dark (6–13:1); `fg_default`
passes everywhere. Recurring issues:
- **`fg_dim`** is the main nit — fails/borderline on `tokyo-night` (2.5), `dracula` (2.5),
  and warns on `nord`/`one-dark`/`tomorrow-night`/`gruvbox-dark`/`catppuccin-mocha`.
- **`solarized-dark`** is broken wholesale (5/5) — low-contrast *by design* (even
  `fg_default` is 4.1 on surface).
- `nord` also has `orange` 3.5 (warn). `fg_faded` fails on most dark, but that's the
  placeholder tone.

### Light themes — broadly broken
**6 of 7** light themes fail AA on 4–5 of the 5 real text tokens (on surface):
- `yellow`/`cyan`/`orange` fail almost everywhere (yellow as low as **1.6–1.9**),
  because the palettes keep bright accents on near-white.
- `fg_dim` fails on most (the `mix(fg,bg,0.40)` tone is too light on light bg).
- **`github-light` is the only clean one (1/5)** — its accents are deliberately dark
  (blue `#0969da`, green `#1a7f37`, yellow `#9a6700`). It is the model.
- `solarized-light` is worst-by-design (even `fg_default` 3.6 on surface).

## Two root causes + fix direction

1. **Bright accents on light backgrounds.** Override `accent_yellow/cyan/orange` (and
   the minor `red/green/purple`) to darkened values for the failing light themes
   (`ayu-light`, `catppuccin-latte`, `gruvbox-light`, `one-light`, `tomorrow`,
   `solarized-light`), github-light-style. Target ≥4.5:1 on surface.
2. **`fg_dim` blend is too aggressive** (`mix(fg,bg,0.40)`) — marginal even on a few dark
   themes and failing on light. Soften it in light mode (and slightly in dark) so dim
   text holds ≥4.5:1 on surface (≥3:1 minimum).

`solarized` (both modes) and `nord` are intentionally low-contrast palettes — a product
call whether to "fix" them or keep them faithful to upstream.

---

## Text — fg trio + yellow/cyan/orange vs page & surface (AA 4.5:1)
✅ ≥4.5 · ⚠️ 3–4.5 · ❌ <3.  `fg_faded` is a placeholder tone (3:1 floor).

### LIGHT themes
| theme | fg | fg-dim | fg-faded | yellow | cyan | orange | AA-fails/5 (surface) |
|---|---|---|---|---|---|---|---:|
| **ayu-light** | p6.1✅ s5.7✅ | p2.6❌ s2.4❌ | p1.8❌ s1.7❌ | p1.9❌ s1.7❌ | p2.2❌ s2.1❌ | p2.3❌ s2.1❌ | 4/5 |
| **catppuccin-latte** | p7.1✅ s5.2✅ | p5.5✅ s4.1⚠️ | p3.5⚠️ s2.6❌ | p2.3❌ s1.7❌ | p3.3⚠️ s2.4❌ | p2.6❌ s1.9❌ | 4/5 |
| **github-light** | p14.7✅ s13.8✅ | p4.0⚠️ s3.8⚠️ | p2.4❌ s2.2❌ | p4.9✅ s4.6✅ | p4.9✅ s4.6✅ | p5.0✅ s4.7✅ | 1/5 |
| **gruvbox-light** | p10.2✅ s8.5✅ | p3.4⚠️ s2.8❌ | p2.1❌ s1.8❌ | p2.2❌ s1.8❌ | p2.8❌ s2.3❌ | p3.4⚠️ s2.8❌ | 4/5 |
| **one-light** | p10.9✅ s9.8✅ | p3.4⚠️ s3.1⚠️ | p2.1❌ s1.9❌ | p3.1⚠️ s2.8❌ | p4.0⚠️ s3.6⚠️ | p4.7✅ s4.2⚠️ | 4/5 |
| **solarized-light** | p4.1⚠️ s3.6⚠️ | p2.2❌ s1.9❌ | p1.6❌ s1.4❌ | p3.0❌ s2.6❌ | p2.9❌ s2.6❌ | p4.3⚠️ s3.8⚠️ | 5/5 |
| **tomorrow** | p8.5✅ s7.4✅ | p3.0⚠️ s2.6❌ | p2.0❌ s1.7❌ | p1.9❌ s1.6❌ | p3.4⚠️ s2.9❌ | p2.5❌ s2.2❌ | 4/5 |

### DARK themes
| theme | fg | fg-dim | fg-faded | yellow | cyan | orange | AA-fails/5 (surface) |
|---|---|---|---|---|---|---|---:|
| **ayu-dark** | p10.3✅ s9.7✅ | p4.3⚠️ s4.1⚠️ | p2.5❌ s2.4❌ | p10.1✅ s9.6✅ | p13.3✅ s12.6✅ | p8.5✅ s8.1✅ | 1/5 |
| **ayu-mirage** | p12.1✅ s11.5✅ | p5.3✅ s5.0✅ | p3.1⚠️ s3.0❌ | p11.1✅ s10.6✅ | p10.7✅ s10.1✅ | p8.4✅ s8.0✅ | 0/5 |
| **catppuccin-mocha** | p11.3✅ s8.7✅ | p4.9✅ s3.8⚠️ | p3.0❌ s2.3❌ | p12.9✅ s9.9✅ | p11.0✅ s8.4✅ | p9.3✅ s7.1✅ | 1/5 |
| **dracula** | p13.4✅ s11.3✅ | p3.0⚠️ s2.5❌ | p3.4⚠️ s2.9❌ | p12.7✅ s10.7✅ | p10.3✅ s8.7✅ | p8.4✅ s7.0✅ | 1/5 |
| **github-dark** | p12.3✅ s11.2✅ | p5.0✅ s4.6✅ | p2.9❌ s2.6❌ | p7.5✅ s6.9✅ | p9.1✅ s8.3✅ | p7.5✅ s6.8✅ | 0/5 |
| **gruvbox-dark** | p10.7✅ s8.5✅ | p4.8✅ s3.8⚠️ | p3.0❌ s2.3❌ | p8.7✅ s6.8✅ | p7.0✅ s5.5✅ | p5.8✅ s4.6✅ | 1/5 |
| **nord** | p9.2✅ s7.4✅ | p4.4⚠️ s3.6⚠️ | p2.8❌ s2.3❌ | p8.0✅ s6.4✅ | p6.2✅ s5.0✅ | p4.4⚠️ s3.5⚠️ | 2/5 |
| **one-dark** | p6.6✅ s7.2✅ | p3.3⚠️ s3.7⚠️ | p2.3❌ s2.5❌ | p8.1✅ s8.9✅ | p5.9✅ s6.5✅ | p5.7✅ s6.2✅ | 1/5 |
| **solarized-dark** | p4.7✅ s4.1⚠️ | p2.6❌ s2.2❌ | p1.9❌ s1.6❌ | p4.7✅ s4.1⚠️ | p4.8✅ s4.1⚠️ | p3.3⚠️ s2.8❌ | 5/5 |
| **tokyo-night** | p10.6✅ s9.6✅ | p2.8❌ s2.5❌ | p1.9❌ s1.7❌ | p8.5✅ s7.8✅ | p10.0✅ s9.1✅ | p8.4✅ s7.6✅ | 1/5 |
| **tomorrow-night** | p9.8✅ s8.5✅ | p4.4⚠️ s3.8⚠️ | p2.7❌ s2.4❌ | p10.3✅ s8.9✅ | p8.0✅ s6.9✅ | p6.6✅ s5.8✅ | 1/5 |

## brand_pito #5170ff — logo (on page) + chatbox/echo border (non-text, 3:1)
| theme | mode | vs page | vs surface | verdict |
|---|---|---:|---:|---|
| ayu-light | light | 4.00 | 3.73 | OK |
| catppuccin-latte | light | 3.63 | 2.66 | faint border on surface (2.7) |
| github-light | light | 4.11 | 3.86 | OK |
| gruvbox-light | light | 3.62 | 2.99 | faint border on surface (3.0) |
| one-light | light | 3.94 | 3.54 | OK |
| solarized-light | light | 3.81 | 3.35 | OK |
| tomorrow | light | 4.11 | 3.57 | OK |
| ayu-dark | dark | 4.70 | 4.45 | OK |
| ayu-mirage | dark | 3.78 | 3.59 | OK |
| catppuccin-mocha | dark | 3.99 | 3.06 | OK |
| dracula | dark | 3.47 | 2.92 | faint border on surface (2.9) |
| github-dark | dark | 4.61 | 4.21 | OK |
| gruvbox-dark | dark | 3.59 | 2.82 | faint border on surface (2.8) |
| nord | dark | 3.04 | 2.45 | faint border on surface (2.4) |
| one-dark | dark | 3.41 | 3.75 | OK |
| solarized-dark | dark | 3.65 | 3.16 | OK |
| tokyo-night | dark | 4.16 | 3.79 | OK |
| tomorrow-night | dark | 4.02 | 3.50 | OK |
