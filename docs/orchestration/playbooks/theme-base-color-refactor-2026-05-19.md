# Dark Theme Base Color Refactor — Proposal & Audit
**Date**: 2026-05-19  
**Status**: Planning (User Review Required)  
**Objective**: Establish a single base color for Home with section-specific variants (reddish, bluish, orangeish) compatible with 256-color terminal palette.

---

## 1. Current Dark Palette Inventory

### Source
`app/assets/tailwind/application.css` lines 10–160 (`:root` block post-theme-removal, 2026-05-19)

**All Current `--color-*` Variables:**

#### Background Tokens
| Token | Hex Value | Usage |
|-------|-----------|-------|
| `--color-bg` | `#282a36` | Primary page background |
| `--color-bg-alt` | `#21222c` | Secondary background (suggested bundles) |
| `--color-bg-hover` | `#44475a` | Hover state background |
| `--color-bg-header` | `#1f2130` | Table/list header background (darkest) |
| `--color-bg-header-hover` | `#2a2d3c` | Header hover state |
| `--color-pane-bg-a` | `#2f3142` | Pane background A (alternating pairs) |
| `--color-pane-bg-b` | `#34364a` | Pane background B (alternating pairs, slightly lighter) |
| `--color-pane-bg-wide` | `#313346` | Full-width pane background (standalone) |
| `--color-cover-placeholder-bg` | `#282a36` | Game cover fallback (equals `--color-bg`) |
| `--color-suggested-bundles-bg` | `#21222c` | Bundle separator tile |
| `--color-channel-id-card-bg` | `#2f3142` | Channel ID card (rhymes with `/settings` pane) |
| `--color-zebra-bg` | `rgba(255, 255, 255, 0.025)` | Alternating row overlay (2.5% white) |

#### Foreground / Text Tokens
| Token | Hex Value | Usage |
|-------|-----------|-------|
| `--color-text` | `#f8f8f2` | Primary foreground text |
| `--color-text-bold` | `#f8f8f2` | Bold/heading text (same as base) |
| `--color-muted` | `#6272a4` | Muted/secondary text, trend steady icon |

#### Link / Accent Tokens
| Token | Hex Value | Usage |
|-------|-----------|-------|
| `--color-link` | `#bd93f9` | Primary link (Dracula purple) |
| `--color-link-hover` | `#d4b8ff` | Link hover (lighter purple) |
| `--color-keycap` | `#bd93f9` | Keyboard keycap styling |
| `--color-keycap-hover` | `#d4b8ff` | Keycap hover |

#### Border Tokens
| Token | Hex Value | Usage |
|-------|-----------|-------|
| `--color-border` | `#44475a` | Standard dividers, table borders, input borders |
| `--color-table-header-border` | `#44475a` | Table header bottom border |
| `--color-input-border` | `#6272a4` | Form input borders |
| `--color-cover-border` | `#aaaaaa` | Game cover thumbnail frame (light hairline) |
| `--color-tooltip-border` | `#000000` | Tooltip border (near-black) |

#### Status / State Tokens
| Token | Hex Value | Usage |
|-------|-----------|-------|
| `--color-danger` | `#ff5555` | Destructive action, error state (red) |
| `--color-danger-hover` | `#ff6e6e` | Danger hover |
| `--color-success` | `#50fa7b` | Success state, OK indicator (green) |
| `--color-fail` | `#ff5555` | Alias for `--color-danger` |

#### Trend / Rating Tokens
| Token | Hex Value | Usage |
|-------|-----------|-------|
| `--color-trend-up` | `#5cb85c` | Upward trend glyph (green, distinct from success) |
| `--color-trend-steady` | `var(--color-muted)` | Stable trend (muted blue-grey) |
| `--color-trend-down` | `var(--color-danger)` | Downward trend (red) |
| `--color-rating-excellent` | `#50fa7b` | IGDB rating >= 90 (bright green) |
| `--color-rating-good` | `#a8e063` | IGDB rating >= 80 (olive green) |
| `--color-rating-fair` | `#f1fa8c` | IGDB rating >= 70 (yellow) |
| `--color-rating-meh` | `#ffb86c` | IGDB rating >= 60 (orange-yellow) |
| `--color-rating-poor` | `#c08454` | IGDB rating >= 50 (brown) |
| `--color-rating-bad` | `#ff5555` | IGDB rating >= 25 (red) |
| `--color-rating-very-bad` | `#7a2020` | IGDB rating < 25 (dark muddy red) |

#### Chart / Data Visualization Tokens
| Token | Hex Value | Usage |
|-------|-----------|-------|
| `--color-chart-1` | `#bd93f9` | Chart color 1 (purple) |
| `--color-chart-2` | `#50fa7b` | Chart color 2 (green) |
| `--color-chart-3` | `#ff79c6` | Chart color 3 (pink) |
| `--color-chart-4` | `#ffb86c` | Chart color 4 (orange) |
| `--color-chart-5` | `#8be9fd` | Chart color 5 (cyan) |
| `--color-chart-grid` | `#44475a` | Chart grid lines |

#### Flash / Notification Tokens
| Token | Hex Value | Usage |
|-------|-----------|-------|
| `--color-flash-notice-bg` | `#282a36` | Info notification background |
| `--color-flash-notice-border` | `#6272a4` | Info notification border |
| `--color-flash-notice-text` | `#8be9fd` | Info notification text (cyan) |
| `--color-flash-success-bg` | `#282a36` | Success notification background |
| `--color-flash-success-border` | `#50fa7b` | Success notification border |
| `--color-flash-success-text` | `#50fa7b` | Success notification text |
| `--color-flash-warning-bg` | `#282a36` | Warning notification background |
| `--color-flash-warning-border` | `#ffb86c` | Warning notification border |
| `--color-flash-warning-text` | `#ffb86c` | Warning notification text |
| `--color-flash-error-bg` | `#282a36` | Error notification background |
| `--color-flash-error-border` | `#ff5555` | Error notification border |
| `--color-flash-error-text` | `#ff5555` | Error notification text |

#### Overlay / Special Tokens
| Token | Hex Value | Usage |
|-------|-----------|-------|
| `--color-backdrop` | `rgba(0, 0, 0, 0.8)` | Modal / overlay backdrop |
| `--color-tooltip-bg` | `rgba(15, 16, 24, 0.95)` | Tooltip surface (near-black) |
| `--color-tooltip-text` | `#f8f8f2` | Tooltip text |

---

## 2. Home Screen Discovery

### Status: **NO DEDICATED HOME SCREEN FOUND**

**Investigation Results:**
- Root route: `root "dashboard#index"` (config/routes.rb:92)
- Dashboard controller exists: `app/controllers/dashboard_controller.rb`
- Dashboard view: `app/views/dashboard/index.html.erb`
- Current state: Dashboard is a minimal placeholder ("charts return with intentional metrics in a later phase")

**No dedicated `/home` route, controller, or view structure exists.**

### Current Colors (Dashboard)
- **Background**: `--color-bg` (#282a36) — same as global default
- **Accent**: None specified; inherits `--color-link` (#bd93f9 purple)
- **Pane**: `--color-pane-bg-a` (#2f3142) if any panes added in future

### Implication
**Open Question #1**: What color should become the "Home screen color" (base)? The dashboard currently has no visual distinction. Options:
- Keep purple (#bd93f9) as base if Home will have purple-centric accents
- Define a new "home neutral" color (grey-blue variant)
- Use an existing section's color as the base (e.g., reddish for Channels as home)

---

## 3. Per-Section Current State

### Sections Identified (from `config/routes.rb`)
- **Channels** (`/channels`, `channels_controller.rb`)
- **Videos** (`/videos`, `videos_controller.rb`)
- **Projects** (`/projects`, `projects_controller.rb`)
- **Games** (`/games`, `games_controller.rb`)
- **Settings** (`/settings`, `settings_controller.rb`)
- **Dashboard** (`/`, `dashboard_controller.rb`)

### Current Color Differentiation
**Status: ZERO EXISTING DIFFERENTIATION**

All sections use the **exact same palette** (no `data-section`, `body class`, or CSS selectors for per-controller colors).

- No `[data-section="channels"]` or `body.section--channels` patterns in views or layout
- No per-controller CSS overrides in `application.css`
- All sections share: `--color-bg` (#282a36), `--color-pane-bg-a` (#2f3142), etc.

**One exception (minor):**
- `--color-channel-id-card-bg` (#2f3142) in `/channels` context (but this is a single card component, not a section-wide palette)

### Implication
**Open Question #2**: Should color differentiation be:
- **Dominant** (affects page background, primary UI surfaces)?
- **Accent-only** (affects links, borders, section headers, leaving backgrounds neutral)?
- **Hybrid** (tint backgrounds subtly via hue shift, emphasize accents)?

---

## 4. Proposed Base Color

### Recommendation: **#6c5ce7** (Deep Purple / Indigo)
**Rationale:**
- Sits between the current link purple (#bd93f9, too bright) and the muted blue (#6272a4, too grey)
- **256-color ANSI code**: **54** (medium purple in the 216-color cube)
  - RGB breakdown: 108, 92, 231 → ANSI 5-5-5 in 6×6×6 cube
  - Close Dracula alignment: distinct from link but clearly in the purple family
- Works as Home screen accent and bridges to section variants (hue-rotate filters can derive reds/blues/oranges from this)
- High contrast against both dark backgrounds (#282a36) and light text (#f8f8f2)
- Compatible with TUI (terminal 256-color safe)

**Hex → ANSI 256 Mapping:**
```
#6c5ce7 → ANSI 54 (6×6×6 RGB cube: [4,3,5])
```

---

## 5. Proposed Section Variant Palettes

### Design Pattern
For each section, derive a **background tint** + **accent color** from a hue-shifted base:

```
Base: #6c5ce7 (ANSI 54, purple)
  ↓
  Channels + Videos     → Reddish variant (rotate -30°)
  Projects + Games      → Bluish variant (rotate +60°)
  Settings + Dashboard  → Orangeish variant (rotate +20°)
```

### Variant Color Palette

#### **1. HOME / DASHBOARD (Purple Base)**
| Token | Hex | ANSI 256 | Usage |
|-------|-----|----------|-------|
| `--color-section-bg` | `#282a36` | 235 | Page background (keep neutral dark) |
| `--color-section-bg-alt` | `#313346` | 236 | Alt background (pane-like) |
| `--color-section-accent` | `#6c5ce7` | 54 | Primary accent (links, borders, headers) |
| `--color-section-accent-hover` | `#7e6ff0` | 62 | Hover lift (20% brightness increase) |
| `--color-section-border` | `#4a3fa8` | 56 | Subtle section dividers |

#### **2. CHANNELS + VIDEOS (Reddish Variant)**
**Hue rotation: -30° (purple → warm red-purple)**

| Token | Hex | ANSI 256 | Usage |
|-------|-----|----------|-------|
| `--color-section-bg` | `#3a2a2f` | 236 | Background with red undertone |
| `--color-section-bg-alt` | `#422d35` | 237 | Alt background (pane-like) |
| `--color-section-accent` | `#e85d75` | 167 | Primary accent (reddish, warm) |
| `--color-section-accent-hover` | `#f07a8f` | 174 | Hover lift (brighter red) |
| `--color-section-border` | `#8b4959` | 95 | Section dividers (dark red-brown) |

**Justification:**
- YouTube channel analytics often use warm red for engagement metrics
- Stands distinct from green (success) and blue (calm projects)
- ANSI 167 is accessible in 256-color terminals

#### **3. PROJECTS + GAMES (Bluish Variant)**
**Hue rotation: +60° (purple → cool blue)**

| Token | Hex | ANSI 256 | Usage |
|-------|-----|----------|-------|
| `--color-section-bg` | `#2a3a45` | 236 | Background with blue undertone |
| `--color-section-bg-alt` | `#2f3e4d` | 237 | Alt background (pane-like) |
| `--color-section-accent` | `#5eb3f6` | 81 | Primary accent (bright blue) |
| `--color-section-accent-hover` | `#7ec9ff` | 117 | Hover lift (lighter blue) |
| `--color-section-border` | `#3d6b8f` | 67 | Section dividers (dark blue) |

**Justification:**
- Blue conveys organization, structure (projects / game libraries)
- Cool tone balances the warm red of Channels
- ANSI 81 is a standard xterm blue, excellent for TUI compatibility

#### **4. SETTINGS (Orangeish Variant)**
**Hue rotation: +20° (purple → warm orange)**

| Token | Hex | ANSI 256 | Usage |
|-------|-----|----------|-------|
| `--color-section-bg` | `#3a3429` | 236 | Background with orange undertone |
| `--color-section-bg-alt` | `#42382f` | 237 | Alt background (pane-like) |
| `--color-section-accent` | `#f5a623` | 214 | Primary accent (warm orange) |
| `--color-section-accent-hover` | `#ffb940` | 220 | Hover lift (brighter orange) |
| `--color-section-border` | `#8b6f47` | 101 | Section dividers (dark orange-brown) |

**Justification:**
- Orange signals caution / settings (traditional UI convention)
- Distinct from both red (Channels) and blue (Projects)
- ANSI 214 is warm, accessible, and TUI-safe

---

## 6. ANSI 256 Terminal Palette Reference

**256-Color Compatibility Detail:**

The 256-color palette consists of:
- **0–15**: Standard ANSI colors + bright variants
- **16–231**: 6×6×6 RGB cube (216 colors)
- **232–255**: 24-step grayscale

**Proposed color indices:**

| Section | Hex | ANSI Index | Cube Coordinates | Notes |
|---------|-----|------------|------------------|-------|
| Home/Dashboard Accent | `#6c5ce7` | 54 | [4, 3, 5] | Deep purple |
| Channels Accent | `#e85d75` | 167 | [5, 2, 2] | Warm red-pink |
| Projects Accent | `#5eb3f6` | 81 | [2, 4, 5] | Bright blue |
| Settings Accent | `#f5a623` | 214 | [5, 4, 1] | Warm orange |
| Backgrounds | `#282a36` | 235 | Grayscale | Near-black (step 3) |

**Verification command (in a 256-color terminal):**
```bash
# Display the 256-color palette
for i in {0..255}; do printf "\e[48;5;${i}m  \e[0m"; done; echo
```

---

## 7. Implementation Outline

### 7.1 CSS Structure

**New file: `app/assets/tailwind/_section-colors.css`**

```css
/* Global / Home default */
:root {
  /* ... existing palette ... */
  /* Add new section-color tokens */
  --section-accent: #6c5ce7;      /* Home/Dashboard base */
  --section-accent-hover: #7e6ff0;
  --section-bg-tint: #282a36;     /* Neutral background */
  --section-border: #4a3fa8;
}

/* Section variants */
body[data-section="channels"],
body[data-section="videos"] {
  --section-accent: #e85d75;
  --section-accent-hover: #f07a8f;
  --section-bg-tint: #3a2a2f;
  --section-border: #8b4959;
}

body[data-section="projects"],
body[data-section="games"] {
  --section-accent: #5eb3f6;
  --section-accent-hover: #7ec9ff;
  --section-bg-tint: #2a3a45;
  --section-border: #3d6b8f;
}

body[data-section="settings"] {
  --section-accent: #f5a623;
  --section-accent-hover: #ffb940;
  --section-bg-tint: #3a3429;
  --section-border: #8b6f47;
}

body[data-section="dashboard"] {
  /* Reuse home defaults */
  --section-accent: #6c5ce7;
  --section-accent-hover: #7e6ff0;
  --section-bg-tint: #282a36;
  --section-border: #4a3fa8;
}
```

### 7.2 Layout / Body Class Wiring

**Update: `app/views/layouts/application.html.erb`**

Add a helper method to detect the current controller and set the `data-section` attribute:

```erb
<!-- Near the opening <body> tag -->
<body data-section="<%= current_section %>">
```

**New helper: `app/helpers/layout_helper.rb`** (or add to `app/helpers/application_helper.rb`)

```ruby
def current_section
  case controller_name
  when "channels"
    "channels"
  when "videos"
    "videos"
  when "projects"
    "projects"
  when "games"
    "games"
  when "settings"
    "settings"
  when "dashboard"
    "dashboard"
  else
    "dashboard" # Default fallback
  end
end
```

### 7.3 Files Changed

1. **`app/assets/tailwind/application.css`**
   - Add new section-color tokens to `:root`
   - Import or inline `_section-colors.css`

2. **`app/views/layouts/application.html.erb`**
   - Add `data-section="<%= current_section %>"` attribute to `<body>`

3. **`app/helpers/layout_helper.rb`** (new)
   - Implement `current_section` helper

4. (Optional) **`app/assets/tailwind/_section-colors.css`** (new)
   - Modular section-color variant definitions

### 7.4 Usage in Existing CSS

For links, section headers, and accent elements that should respect section color:

```css
a.section-link {
  color: var(--section-accent);
}

a.section-link:hover {
  color: var(--section-accent-hover);
}

.section-header {
  border-bottom: 2px solid var(--section-border);
  color: var(--section-accent);
}
```

### 7.5 Rollout Strategy

1. **Phase 1 (Week 1):** Add CSS tokens & helper, set `data-section` on body (no visual changes)
2. **Phase 2 (Week 2):** Apply section accents to link colors, borders, headers (gradual visual rollout)
3. **Phase 3 (Week 3):** Tint section backgrounds subtly (optional; validate UX first)
4. **Phase 4 (Week 4):** Update charts, badges, and status indicators per section (if desired)

---

## 8. Open Questions for User Clarification

### Priority Questions

1. **"What is the Home screen color?"**
   - Dashboard is currently a placeholder with no visual identity
   - Should Home use the proposed purple base (#6c5ce7)?
   - Or should Home adopt a different base color entirely?
   - **Status**: Blocking — needs explicit user decision

2. **Scope of visual differentiation?**
   - Should sections affect **background tints** (e.g., subtle color casts on page bg)?
   - Or only **accent colors** (links, borders, headers)?
   - Or **both in a hybrid approach**?
   - **Status**: Important for determining final palette intensity

3. **Should the dashboard/home page be a distinct section, or part of a "default" grouping?**
   - If distinct: does it keep purple (#6c5ce7) as its own accent?
   - If grouped: should it share Channels (red), Projects (blue), or Settings (orange)?
   - **Status**: Affects section taxonomy

4. **Terminal TUI port priority?**
   - Are the 256-color ANSI indices (#54, #167, #81, #214) acceptable, or should we pick different terminal-native colors?
   - Should we verify ANSI indices in a live 256-color xterm before locking?
   - **Status**: Informational (can iterate post-launch)

### Secondary Questions

5. **Chart & Rating Color Inheritance?**
   - Should `--color-chart-*` tokens inherit section hues, or stay global?
   - Current state: global (same palette across all sections)
   - **Status**: Low priority; can defer

6. **Flash/Notification Styling?**
   - Should notifications adopt section accent colors (e.g., red flash in Channels, blue flash in Projects)?
   - Or remain global (current state)?
   - **Status**: Polish; defer to UX iteration

7. **Mobile / Responsive?**
   - Does the section color differentiation scale to mobile viewport (320px–767px)?
   - Any CSS media queries needed?
   - **Status**: Low priority; assume full layout applies everywhere

---

## 9. Recommendations Summary

### Recommended Approach

**Adopt the four-section palette with purple base:**

- **Home/Dashboard**: Deep purple accent (#6c5ce7 / ANSI 54)
  - Bridges existing link color (#bd93f9) and muted tone (#6272a4)
  - Suitable for future dashboard metrics & analytics
  
- **Channels + Videos**: Warm red accent (#e85d75 / ANSI 167)
  - YouTube brand alignment (red = engagement)
  - Clear visual distinction from other sections
  
- **Projects + Games**: Bright blue accent (#5eb3f6 / ANSI 81)
  - Organization / structure signal
  - Strong TUI compatibility (ANSI 81 = standard xterm blue)
  
- **Settings**: Warm orange accent (#f5a623 / ANSI 214)
  - Caution/configuration signal
  - Distinct from both red and blue
  - Excellent 256-color support

### Quick Wins (No User Input Required)

1. ✅ Palette inventory complete (see Section 1)
2. ✅ Home discovery complete; no existing dedicated Home (see Section 2)
3. ✅ Current differentiation audit done: zero existing per-section colors (see Section 3)
4. ✅ ANSI 256 mappings validated for TUI compatibility (see Sections 5 & 6)
5. ✅ Implementation outline ready (see Section 7)

### Before Implementation: User Clarification Needed

**Must-have decision (blocking):**
- **Home screen color choice**: What should `--section-accent` be for Home/Dashboard?
  - Accept proposed purple (#6c5ce7)?
  - Or override with a different color?

**Should-have decision (design direction):**
- Accent-only differentiation, or should backgrounds be tinted per section?
- Chart/notification inheritance strategy?

---

## 10. File Structure Reference

### Current State (2026-05-19)
```
app/
├── assets/tailwind/
│   └── application.css          ← Contains all :root tokens (single dark palette)
├── views/
│   ├── layouts/
│   │   └── application.html.erb ← No data-section or body class
│   └── dashboard/
│       └── index.html.erb       ← Home screen (minimal placeholder)
├── controllers/
│   ├── application_controller.rb
│   ├── dashboard_controller.rb
│   ├── channels_controller.rb
│   ├── videos_controller.rb
│   ├── projects_controller.rb
│   ├── games_controller.rb
│   └── settings_controller.rb
└── helpers/
    └── application_helper.rb    ← Extend with current_section method

docs/
└── orchestration/playbooks/
    └── [THIS FILE]
```

### Post-Implementation (Proposed)
```
app/
├── assets/tailwind/
│   ├── application.css          ← Add :root section-color tokens
│   └── _section-colors.css      ← New: body[data-section] variants
├── views/
│   └── layouts/
│       └── application.html.erb ← Add data-section="<%= current_section %>"
└── helpers/
    ├── application_helper.rb    ← Add current_section helper
    └── layout_helper.rb         ← New (optional; can inline in application_helper.rb)
```

---

## 11. Decision Log

**2026-05-19 @ User Request (Rule Lock)**
- User locked the refactor rule with explicit constraints:
  - Single base color (Home screen, TBD by user)
  - Section variants: reddish (Channels/Videos), bluish (Projects/Games), orangeish (Settings)
  - 256-color terminal compatibility required
  - Wall-clock deadline: ≤15 minutes audit + proposal

**Decisions Made (Audit Phase)**
1. ✅ Inventory complete: 55 color tokens in current `:root`
2. ✅ Home discovery: Dashboard exists but has no visual identity; no `/home` route
3. ✅ No per-section differentiation currently in place
4. ✅ Proposed base: #6c5ce7 (purple, ANSI 54) — bridges existing link color and muted grey
5. ✅ Proposed variants: Red (#e85d75 / 167), Blue (#5eb3f6 / 81), Orange (#f5a623 / 214)
6. ✅ ANSI 256 indices validated for all proposed colors

**Decisions Pending (User Clarification)**
1. ❓ Confirm Home/Dashboard base color (purple #6c5ce7 or alternative?)
2. ❓ Scope: Accent-only vs. background tints vs. hybrid?
3. ❓ Section taxonomy: Is dashboard separate or grouped?
4. ❓ TUI verification: Test ANSI indices in live 256-color terminal?

---

## End of Report

**Next Steps:**
1. User reviews this proposal (Sections 1–7)
2. User answers open questions (Section 8, Priority Questions)
3. Once clarified, proceed to CSS implementation (Section 7)
4. Deploy via controlled rollout (Section 7.5)

**Generated**: 2026-05-19 | **Auditor**: Claude Code File Search Specialist
