# PR #62 — validation queue (every commit on `themes`)

> Branch `themes` (PR #62, **do not merge until validated**). COMPLETE ordered
> commit history (oldest → newest) — every commit lands here for evaluation.
> Tick a box once validated. Inspect any commit with `git show <sha>`.

Total commits: **172**

## Commits

1. [ ] `c61d6dc3` (2026-06-06) — Plan: themes — multi-theme system + /theme command (docs/themes.md)
2. [ ] `e6699207` (2026-06-06) — P1: theme engine core (Mix/Definition/Registry) + tokyo-night + dracula
3. [ ] `140facc4` (2026-06-06) — P2: theme CSS generator + pito:themes:export rake + wire themes.css
4. [ ] `1374aa46` (2026-06-06) — P4: theme persistence: AppSetting.theme + dynamic data-theme + endpoint
5. [ ] `b66bc44b` (2026-06-06) — Restructure docs/themes.md into granular atomic-task plan + refined /theme scope
6. [ ] `44cc5efe` (2026-06-06) — P3: 16 remaining theme palettes + regenerate themes.css
7. [ ] `b3f01da6` (2026-06-06) — P5: /theme command core (apply/preview/reset + vocab + autocomplete + --help)
8. [ ] `ceddc71f` (2026-06-06) — P6: slash alias system + /theme ls alias of /theme list
9. [ ] `b90bcdb0` (2026-06-06) — Reject excess command arguments + stop autocomplete after slots filled
10. [ ] `1a1b1f65` (2026-06-06) — P7: /theme list System message + #preview/#apply hashtag replies
11. [ ] `16c874ec` (2026-06-06) — P8: /theme preview sidebar (grouped Dark/Light, current marker, hint)
12. [ ] `a43a431e` (2026-06-06) — P9: theme preview/apply JS (theme_nav_controller) + Vitest
13. [ ] `c98602b5` (2026-06-06) — P10: route hardcoded colors through tokens (light-theme readiness)
14. [ ] `65f36f4d` (2026-06-06) — P11: verification green (rspec/npm/rubocop) — tick T11.1/T11.2
15. [ ] `1a6886bd` (2026-06-06) — Fix Zeitwerk eager-load: ignore theme definitions dir
16. [ ] `015ab96c` (2026-06-06) — docs: flip T11.6 [x] in themes.md
17. [ ] `00aabb7d` (2026-06-06) — Plan: P12 — in-place #preview/#apply via reusable diff-reveal engine
18. [ ] `18d06e5a` (2026-06-06) — P12a: #preview/#apply transform the theme list in place (backend)
19. [ ] `e0e7899e` (2026-06-06) — Plan: P13-P15 — generalize replies into a reusable follow-up engine
20. [ ] `7a4f1d8d` (2026-06-06) — P13: reusable follow-up engine (generator/router/registry/dispatch)
21. [ ] `37594429` (2026-06-06) — Plan: P13 done; add Sonnet-first parallelization note for P14/P15
22. [ ] `4e623080` (2026-06-06) — P14: confirmations via the follow-up engine (echo + append, consume)
23. [ ] `d65fb8bf` (2026-06-06) — P15: theme list follow-up via the engine (#&lt;handle&gt; preview/apply)
24. [ ] `bca98493` (2026-06-06) — P12b: reusable diff-reveal engine (dual granularity)
25. [ ] `087e0430` (2026-06-06) — Fix stale router spec comment (ConfirmationRouter retired in P14)
26. [ ] `00ac47c1` (2026-06-06) — Document plan-author (plan mode) + plan-runner (coding) workflow
27. [ ] `dd90fd4e` (2026-06-06) — Plan: copy engine — centralized witty dictionaries (P1-P4)
28. [ ] `28b57d11` (2026-06-06) — Copy engine core (Pito::Copy.render: string|array, interpolation, deterministic sampler)
29. [ ] `74c30678` (2026-06-06) — Plan: copy engine decisions locked (Pito::Copy, pito.copy.\*, uniform, full sweep)
30. [ ] `2795daea` (2026-06-06) — pito.copy namespace + pito:copy:audit rake
31. [ ] `942cc831` (2026-06-06) — Migrate existing dictionaries onto the copy engine
32. [ ] `767f5463` (2026-06-06) — Wire slash replies through the copy engine
33. [ ] `4b87067a` (2026-06-06) — Wire hashtag/follow-up replies through the copy engine
34. [ ] `b6150178` (2026-06-06) — Wire chat replies through the copy engine
35. [ ] `e115f7fa` (2026-06-06) — Copy engine P4: fixed replies wired through Pito::Copy
36. [ ] `8c1731c1` (2026-06-06) — Copy engine: accept placeholder vars as kwargs or hash (drop explicit-braces footgun)
37. [ ] `8e16415c` (2026-06-06) — Plan: P5 — standardize every dictionary to 50 variants
38. [ ] `b7550037` (2026-06-06) — P5: relocate single-entry wired copy under pito.copy.\*
39. [ ] `f02a8408` (2026-06-06) — P5: enrich relocated copy to 50 variants
40. [ ] `ad6dd09f` (2026-06-06) — P5: top up dictionaries to 50 + audit below-standard flag
41. [ ] `c737c723` (2026-06-06) — Fix flaky copy specs: load Pito::Copy deterministic sampler globally (parallel CI)
42. [ ] `76200709` (2026-06-06) — Add docs/validations.md — accumulating review queue for PR #62
43. [ ] `b7306009` (2026-06-06) — Plan: games domain (docs/games.md) — repurpose IGDB, P0-P15
44. [ ] `0f601130` (2026-06-06) — Rename /theme command to /themes
45. [ ] `3e372a63` (2026-06-06) — Fix remaining /theme → /themes in switch.rb + comments
46. [ ] `56f5027e` (2026-06-06) — Prettier: reflow docs/themes.md after /themes rename
47. [ ] `fa46fb6a` (2026-06-06) — Rename Pito::Autocomplete → Pito::Suggestions (Ruby)
48. [ ] `f8686b3b` (2026-06-06) — Rename autocomplete route to /suggestions
49. [ ] `b2eee2fe` (2026-06-06) — Rename autosuggest JS controller to pito--suggestions
50. [ ] `d1e52c2c` (2026-06-06) — Rename pito-autosuggest CSS classes to pito-suggestions
51. [ ] `2ee624cb` (2026-06-06) — Rename autocomplete i18n + final Suggestions sweep
52. [ ] `6ac89f3e` (2026-06-06) — Follow-up: revisit & tighten /help after games land
53. [ ] `439e1faf` (2026-06-06) — Games: add last_sync_error + resyncing columns
54. [ ] `7c38461a` (2026-06-06) — Games: drop version-parent/version_title (main titles only)
55. [ ] `f66ebe8a` (2026-06-06) — Games: store all genres, drop primary-genre evaluator
56. [ ] `5652722b` (2026-06-06) — Games: drop dead notes/played_at columns
57. [ ] `6eb9769a` (2026-06-06) — Games: remove orphaned Games::Filter + define real scopes
58. [ ] `a892c024` (2026-06-06) — Fix ScoreBarComponent resyncing? reference
59. [ ] `fc21248d` (2026-06-06) — P2: games schema reconcile green
60. [ ] `330826e9` (2026-06-06) — Prettier: reflow docs after P2 checkbox updates
61. [ ] `d008b182` (2026-06-06) — Remove phantom analytics-sync job chain
62. [ ] `aba3828c` (2026-06-06) — Remove phantom analytics services
63. [ ] `eaf8d1c6` (2026-06-06) — Remove analytics controllers + routes
64. [ ] `ecaf57d6` (2026-06-06) — Remove phantom video-import stack (keep ImportVideosJob)
65. [ ] `3bcfd05b` (2026-06-06) — Remove Video::ThumbnailPreview stub
66. [ ] `8f7719d4` (2026-06-06) — Strip phantom column writes + video_stats refs
67. [ ] `1d253cfc` (2026-06-06) — Remove phantom YoutubeApiCall tracker/quota + clean recurring.yml
68. [ ] `c3cf7a7d` (2026-06-06) — P3: remove phantom video/analytics dead code (green)
69. [ ] `7d9aaa0f` (2026-06-06) — Prettier: reflow docs/follow-up.md (match CI glob)
70. [ ] `94c2ff4b` (2026-06-06) — P4: polymorphic Stat model + Pito::Stats facade (subscribers/views)
71. [ ] `2e25e2a0` (2026-06-06) — P4: move channel stats to Pito::Stats; drop watched_hours
72. [ ] `08b67695` (2026-06-06) — P4: move video views to Pito::Stats; drop videos.view_count
73. [ ] `e1b1399c` (2026-06-06) — P4: Game::StatsRefresh + GameStatsRefreshJob (views = sum linked videos)
74. [ ] `8e325151` (2026-06-06) — P4: phase-end — flip T4.x checkboxes (Stat infra complete)
75. [ ] `37442d73` (2026-06-06) — Pito::Stack: api_requests table (T5.1)
76. [ ] `5464af6b` (2026-06-06) — Pito::Stack: ApiRequest model + window scopes (T5.2)
77. [ ] `803e8457` (2026-06-06) — Pito::Stack: facade + Voyage/Youtube/Igdb provider counts (T5.3)
78. [ ] `6b13ba3d` (2026-06-06) — Pito::Stack::Local: db size + record counts + usage (T5.4)
79. [ ] `c066dee0` (2026-06-06) — Pito::Stack: track helper + instrument Voyage chokepoint (T5.5a)
80. [ ] `4740920d` (2026-06-06) — Pito::Stack: instrument IGDB Client#post chokepoint (T5.5b)
81. [ ] `63043ef7` (2026-06-06) — Pito::Stack: instrument YouTube auditor chokepoint (T5.5c)
82. [ ] `3d391518` (2026-06-06) — Remove superseded Pito::ExternalApiTracker (replaced by Pito::Stack) (T5.6)
83. [ ] `4d801f1e` (2026-06-06) — P5: Pito::Stack engine complete (api-usage + local tracking) — phase green
84. [ ] `54d892e2` (2026-06-06) — Modular search: Base + Registry + IGDB game-search module (T6.1-T6.3,T6.5)
85. [ ] `4a1c7770` (2026-06-06) — P6: retire dead Game::SearchService + Omnisearch; modular search green (T6.4-T6.6)
86. [ ] `a1c5b922` (2026-06-06) — Fix IGDB credentials lookup (creds is a Hash, not a struct) + client spec (T7.1)
87. [ ] `557e71b3` (2026-06-06) — GameMapper: populate platforms[] from IGDB (T7.2)
88. [ ] `bea85e72` (2026-06-06) — IGDB already-in-library resolver: find-or-stub + sync (T7.3)
89. [ ] `b2d463e0` (2026-06-06) — P7: repair IGDB sync end-to-end (creds/platforms/resolver/specs) — phase green
90. [ ] `7349a381` (2026-06-06) — Fix theme Registry empties after dev reload (load, not require)
91. [ ] `05124807` (2026-06-06) — Fix themes: add slash.help more_hint/fewer_hint i18n + strip 'Esc close' from sidebar hint
92. [ ] `d4456d22` (2026-06-06) — Fix catppuccin-latte low-contrast fg-dim/fg-faded (chatbox + timestamps)
93. [ ] `1e1b2425` (2026-06-06) — validations: log the 4 theme bugs found (3 fixed + 1 to re-test)
94. [ ] `7159b878` (2026-06-06) — P8.1: Game::EmbedText multi-field builder + wire both indexers
95. [ ] `165f5051` (2026-06-06) — P8.2: diff-gated Voyage reindex (embedded_digest) + fix undefined AppSetting.voyage_configured?
96. [ ] `c62ebc57` (2026-06-06) — Fix follow-up affordance handle contrast (text-surface→text-purple)
97. [ ] `14b173b5` (2026-06-06) — Theme current-marker via Pito::Copy (50 variants, real ← char); drop inline copy + bullet
98. [ ] `6d8e1b54` (2026-06-06) — Move help more/fewer affordance hints to pito.copy.\* (50 variants, via Pito::Copy)
99. [ ] `e83b2778` (2026-06-06) — Add channel embedding columns (summary_embedding HNSW + keywords + tags) + has_neighbors
100. [ ] `f90685c4` (2026-06-06) — Channel::VoyageIndexer: multi-field (tags) + digest gate + backfill task
101. [ ] `185ed69a` (2026-06-06) — Specs for SimilarGames + ChannelRecommendation on populated embeddings (P8 phase-end)
102. [ ] `41d48f3c` (2026-06-06) — Game detail message component (score + ttb-with-footage + cover) + DetailMessage payload builder
103. [ ] `faf903da` (2026-06-06) — Drop unbacked channels.tags from index; wire channel keywords from YouTube branding into sync
104. [ ] `a64c84d4` (2026-06-06) — Plan: video-indexing phase (P9.5) + amend command surface (ids/update/link) + 3-way recommendations + nightly UTC sync orchestration
105. [ ] `7f167435` (2026-06-06) — Video embedding core: Video::EmbedText + embedded_digest + Video::VoyageIndexer (digest-gated)
106. [ ] `b0e5d742` (2026-06-06) — Wire video embedding into import + reindex_videos backfill (atomic per-video jobs)
107. [ ] `bf8118c8` (2026-06-06) — Adopt design B: channel = its videos (drop channel embedding + description/keywords; channel↔game via video-NN grouping)
108. [ ] `155c82e9` (2026-06-06) — Mark P9.5 complete (video embeddings + design B channel↔game)
109. [ ] `e8e9827b` (2026-06-06) — Guard debounced suggestion fetches against torn-down document (fix CI vitest teardown flake)
110. [ ] `10b63bc4` (2026-06-06) — list games: real library query with IDs + follow-up-able (game_list)
111. [ ] `b1d3e76c` (2026-06-06) — Grammar: show/delete chat specs (title slot) + ls/rm aliases
112. [ ] `60d24e54` (2026-06-06) — show game &lt;id|title&gt;: detail message + witty not-found (Pito::Copy)
113. [ ] `0563154b` (2026-06-06) — delete/rm game &lt;id|title&gt;: confirmation + Executor game_delete branch (destroy on confirm)
114. [ ] `3021b6d6` (2026-06-06) — Follow-up: #&lt;h&gt; show &lt;id&gt; on a game list appends the detail card (game_list handler)
115. [ ] `9f794e49` (2026-06-06) — Update dispatcher specs: :show now has a handler, use :find as the unregistered example
116. [ ] `50d421ed` (2026-06-06) — update game ownership &lt;id&gt; &lt;platforms&gt;: set GamePlatformOwnership (tolerant list)
117. [ ] `043afe7c` (2026-06-06) — link/unlink video&lt;&gt;game chat verbs (video_game_links)
118. [ ] `5f63d9ce` (2026-06-06) — Game-title ghosting for show/delete chat verbs
119. [ ] `6ee35688` (2026-06-06) — Games picker sidebar + pito--games-nav controller
120. [ ] `0862d344` (2026-06-06) — chat_form: public set-value + submit action for pickers
121. [ ] `a388ea3f` (2026-06-06) — ChatController: no-arg show/rm game opens the games picker
122. [ ] `af66791e` (2026-06-06) — P10 phase-end: games chat verbs + ghost + picker green
123. [ ] `113fe738` (2026-06-07) — P11: /games import sidebar (IGDB search → 5-step progress → detail + enhancement)
124. [ ] `1d1d5440` (2026-06-07) — Flip P11 T11.10 done in plan
125. [ ] `86925fcd` (2026-06-07) — Pito::Recommendations (3-way: similar / game→channel / channel→game)
126. [ ] `0b305198` (2026-06-07) — Game message follow-ups (rm/resync/update-ownership/link · reindex/similar/channel)
127. [ ] `2b7ef67a` (2026-06-07) — Nightly two-stage sync (1:00) + reindex (2:00) orchestration
128. [ ] `da65ec8b` (2026-06-07) — validations.md: full ordered commit checklist (127) + open validation feedback
129. [ ] `bb61a125` (2026-06-07) — Plan: P16 validation-fix tasks (import sidebar / message rendering / score+ttb)
130. [ ] `a274adc7` (2026-06-07) — Fix game-message rendering: timestamp, KV table, platform chips (P16 Group B)
131. [ ] `0df48976` (2026-06-07) — Revive ScoreBarComponent + TimeToBeatComponent multi-stop gradient colors (T16.13)
132. [ ] `3d2cdc10` (2026-06-07) — Fix /games import flow: sidebar UX + steps in sidebar + version_parent filter (P16 Group A)
133. [ ] `0028840c` (2026-06-07) — Extract ShimmerTextComponent + strengthen ScoreBar/TTB specs
134. [ ] `4346d6c7` (2026-06-07) — Document games domain (AGENTS.md + follow-up.md + games.md P15)
135. [ ] `71c42cc6` (2026-06-07) — validations.md: refresh full commit checklist + mark P16 feedback shipped
136. [ ] `b74a1e60` (2026-06-07) — Make ScoreBar + TimeToBeat gradients theme-aware
137. [ ] `406376f9` (2026-06-07) — i18n: inline-copy fix 1 — ImportVideosJob breakdown labels
138. [ ] `f122a96f` (2026-06-07) — i18n: inline-copy fix 2 — ChannelInfoJob stats labels
139. [ ] `eac047d8` (2026-06-07) — i18n: inline-copy fix 3 — inject step labels from server into games-search controller
140. [ ] `80c97d6b` (2026-06-07) — i18n: inline-copy fix 4 — Confirmation::Executor channel fallback + i18n-exception comment
141. [ ] `c7c7f629` (2026-06-07) — i18n: inline-copy fix 5 — Confirmable flash alerts via plain i18n
142. [ ] `4995fcd3` (2026-06-07) — i18n: inline-copy fix 6 — ConversationsController + ApplicationController errors
143. [ ] `795941c4` (2026-06-07) — i18n: inline-copy fix 7 — dedupe DISPLAY_NAMES via pito.game.detail.platform_label
144. [ ] `4f14937a` (2026-06-07) — Remove pre-chat-reboot dead controllers (no routes)
145. [ ] `6fc71200` (2026-06-07) — Remove dead controller concerns (Confirmable, RecentTotpVerification, FriendlyRedirect)
146. [ ] `3cba86c8` (2026-06-07) — Remove dead search services (Everywhere, SearchGames)
147. [ ] `40ab811b` (2026-06-07) — Revert pito.confirmable.\* i18n keys (Confirmable concern deleted)
148. [ ] `6088353d` (2026-06-07) — Remove code-only orphan jobs (zero live callers)
149. [ ] `e44a09e2` (2026-06-07) — Remove dead jobs referencing non-existent constants
150. [ ] `2bff09c7` (2026-06-07) — Purge stranded bulk-op job shims + broken notification-cleanup duplicate (GameDeletion/GameSync/VideoSync/NotificationCleanupJob)
151. [ ] `e22c7fa8` (2026-06-07) — Fix stale doc-comment referencing purged ChannelsController (intent now stashed by chat /connect)
152. [ ] `e5ee39f8` (2026-06-07) — Drop 8 unused video_previews boolean flags (dead scaffolding; keep footages.aspect_ratio — it's probe-populated)
153. [ ] `5da8a59c` (2026-06-07) — Purge unwired VideoPreview (model + table + factory + spec); to be redesigned later
154. [ ] `b19a0ca1` (2026-06-07) — Drop video_previews table + migration + video.rb comment (completes VideoPreview purge)
155. [ ] `beca6c9e` (2026-06-07) — Spec: Voyage nil-embedding raise path + GameImportJob emit_error branch
156. [ ] `4b87e5be` (2026-06-07) — Spec: Game::EmbedText alt_names + ttb_extras + ttb_completionist slots
157. [ ] `0e150f0d` (2026-06-07) — Spec: Channel/Game recommendation limit, views ordering, threshold boundary
158. [ ] `d4e9486a` (2026-06-07) — Spec: GameDetail not-found paths for rm/resync + GameList game_id stamp
159. [ ] `7d16be68` (2026-06-07) — Spec: Executor cancel branches + zero-video disconnect + blank-handle fallback
160. [ ] `0ac38e39` (2026-06-07) — Spec: GameVoyageIndexJob no-op + delegate coverage
161. [ ] `6dbfc2eb` (2026-06-07) — Spec: Pito::Recommendations.similar_games combined genre+year filter intersection
162. [ ] `e0c02007` (2026-06-07) — Spec: Show#resolve_game ILIKE partial-vs-exact prefix behavior
163. [ ] `806bde61` (2026-06-07) — Spec: DetailComponent cover_art_url rescue path + nil-score rendering
164. [ ] `eac1f14f` (2026-06-07) — Spec: NightlyVideoSyncJob no GameStatsRefreshJob when no game links
165. [ ] `4d63c8bb` (2026-06-07) — Spec: Pito::Stack.track rescue + provider to_h shape
166. [ ] `c81d6199` (2026-06-07) — Plan P17 (ScoreBar/TTB widths + ticks + theme-adaptive contrast) + refresh validations checklist
167. [ ] `7a68d178` (2026-06-07) — Theme-adaptive contrast fix for ScoreBar + TTB gradients
168. [ ] `b8702f3a` (2026-06-07) — Resize ScoreBar to 20 cells and TTB to 40 cells
169. [ ] `c735d6e3` (2026-06-07) — Snap ScoreBar needle to its 5% cell midpoint
170. [ ] `b667fd64` (2026-06-07) — Fix TTB tick positioning, brackets, and footage mark
171. [ ] `53675595` (2026-06-07) — Project TTB heat ramp onto the = glyphs over 0..completionist
172. [ ] `25476d38` (2026-06-07) — Round out ScoreBar/TTB specs for the P17 revamp
173. [ ] `02669cf6` (2026-06-07) — Refresh validations checklist (P17 ScoreBar/TTB commits)
174. [ ] `89e1fe65` (2026-06-07) — Messages: one meta line (timestamp · #handle) — drop usage/affordance line; platforms plain text not chips; ScoreBar top spacing
175. [ ] `3832c059` (2026-06-07) — Fix TimeToBeat label rows collapsing onto bar and legend
176. [ ] `164c8a41` (2026-06-07) — Remove follow-up usage/affordance line everywhere (single meta line)
177. [ ] `6ab918fd` (2026-06-07) — Refresh validations checklist (meta-line + TTB + affordance-removal commits)

<!-- ── Smoke-test session (2026-06-07): bugs found + fixed while validating ── -->
178. [x] `e39f6e55` (2026-06-07) — Enter submits chatbox for unauthenticated users (unblocks /login)
179. [x] `a9022cbd` (2026-06-07) — Hide notifications indicator for unauthenticated users
180. [x] `3437a743` (2026-06-07) — Hide post-command dots after synchronous /login (complete the turn)
181. [ ] `2aafed3f` (2026-06-07) — list channels/videos no longer returns the games shelf
182. [ ] `b6f170d7` (2026-06-07) — Add list channels (3-column kv-grid: id, name, handle)
183. [ ] `12c1429a` (2026-06-07) — Channel handle column in cyan
184. [x] `0d764eaa` (2026-06-07) — list verb suggests nouns (channels/videos/games), not release-status
185. [x] `dd61fae9` (2026-06-07) — Hide post-command dots for sidebar fast-paths (emit pito:done)
186. [x] `1182001c` (2026-06-07) — Theme current marker: ASCII '<-' in cyan (chat list + sidebar)
187. [ ] `8a26233f` (2026-06-07) — Hide post-command dots after follow-up replies (broadcast pito:done)
188. [x] `6db6597a` (2026-06-07) — ayu-mirage: lighten foreground for better chatbox contrast
189. [x] `ba09cef5` (2026-06-07) — Help table: auto-size command column (no overflow)
190. [ ] `5dcc9177` (2026-06-07) — Follow-up-aware #handle suggestions (target actions, not legacy add/metrics)
191. [ ] `aeb5a224` (2026-06-07) — Suggestions: ghost first enum value (TAB-completable) instead of <placeholder>
192. [ ] `ab9d22a0` (2026-06-07) — Place caret at end of restored chatbox text (draft + conversation restore)
193. [ ] `4d04a6c3` (2026-06-07) — IGDB search: drop edition/DLC/bundle rows by name (main titles only)
194. [ ] `8f6304a9` (2026-06-07) — Import progress: shimmer the label too (whole row, per-row offset)
195. [ ] `a06d5779` (2026-06-07) — Suggestions: read conversation from uuid param (fixes "add subscribers")
196. [x] `959d85d1` (2026-06-07) — ScoreBar: full-width = fill, precise tick, Pito::Copy label, top spacing
197. [x] `e92c1485` (2026-06-07) — TTB: fill = full-width (no 40 cap)
198. [x] `6a22b50c` (2026-06-07) — ScoreBar/TTB: shrink fill (min-width:0) so gradient spans full width
199. [ ] `47827d4f` (2026-06-07) — IGDB sidebar: shorten shimmer dots (30 → 8; superseded by 27)
200. [x] `9e1fb843` (2026-06-07) — IGDB sidebar: remove exactly 3 shimmer dots (30 → 27)
201. [ ] `ae2bbc4b` (2026-06-07) — Shimmer: ping-pong sweep, return leg 3× faster (75/25, linear)
202. [x] `099135ed` (2026-06-07) — TTB: witty Copy label + guarantee full-width = fill
203. [x] `637e0cf7` (2026-06-07) — ScoreBar gradient: darkest red at the worst end (no light-then-dark jump)
204. [x] `125dcf44` (2026-06-07) — Spec: ScoreBar gradient now 12 color-mix stops
205. [ ] `605ce8b9` (2026-06-07) — Migrate IGDB import step labels to Pito::Copy 50-variant pools
206. [ ] `755e1f48` (2026-06-07) — Build Pito::Game::EnhancedComponent: channel matches + similar games
