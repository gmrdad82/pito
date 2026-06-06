# PR #62 — validation queue (every commit on `themes`)

> Branch `themes` (PR #62, **do not merge until validated**). This is the
> COMPLETE, ordered commit history of the branch (oldest → newest) so each
> change can be reviewed individually. Tick a box once you've validated that
> commit. Inspect any commit with `git show <sha>`.

Total commits: **127**

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

## Open validation feedback (2026-06-07 session)

Tracked for fix in `docs/games.md` → **P16 — validation fixes**:

- [ ] `/games import` sidebar: auto-focus the search field on spawn
- [ ] `/games import` search input styled like the conversation-rename input
- [ ] No thinking/dots indicator on sidebar spawn (nothing sent to backend yet)
- [ ] Search result rows show a small square cover-art thumbnail
- [ ] Shimmer loading indicator (`.` across input width, `.pito-shimmer`) while talking to IGDB
- [ ] Witty `Pito::Copy` for the "no results" message
- [ ] Witty `Pito::Copy` for the "searching…" message
- [ ] IGDB search: MAIN game only — exclude edition variants (`version_parent = null`)
- [ ] Import: the 5 steps run IN THE SIDEBAR (shimmer + random offset), sidebar NOT dismissed
- [ ] Import: Standard message after steps 1–3 (info+cover+score)
- [ ] Import: Enhanced message after steps 4–5 (indexing+recommendations)
- [ ] Import: sidebar stays open with 5 steps marked done (Esc to close)
- [ ] Game detail/enhanced messages render with the standard TIMESTAMP chrome (like every message)
- [ ] Detail card: properly aligned KV table (columns)
- [ ] Detail card: Platforms shown ONLY as your tokens — PlayStation / Switch / Steam — as chips
- [ ] Revive ScoreBarComponent + TimeToBeatComponent exact pane-layout multi-stop gradients (from git history)
