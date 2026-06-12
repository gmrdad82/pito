# Channel card — video-count stat

> Status: draft

## Sign-off

- [x] Drafted — 2026-06-12
- [ ] Audited — _pending_

## North star

The `list channels` card gains a third stat row — the number of videos pito
holds for that channel — rendered as `0 videos` / `1 video` / `N videos`,
positioned **between** the subscriber row and the view row. The same shared
`Pito::Channel::ItemComponent` is reused in the game-enhanced
(recommended-channels) message; that surface must stay exactly as it is — no
video count there. The new behaviour is opt-in via a single optional kwarg.

## Locked decisions

| Topic         | Decision                                                                                                                                                                                        |
| ------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Data source   | `channel.videos.count` (local DB; `has_many :videos`).                                                                                                                                          |
| Pluralisation | `Pito::Copy` keys `videos_count_singular` (`"%{count} video"`) + `videos_count_plural` (`"%{count} videos"`); `0` uses plural. 1-variant keys, mirroring `subscribers_count_*`/`views_count_*`. |
| Opt-in        | New kwarg `show_video_count:` on `ItemComponent#initialize`, default `false`.                                                                                                                   |
| Surfaces      | `list_component.html.erb` passes `show_video_count: true`. `enhanced_component.html.erb` (show game) passes nothing → unchanged.                                                                |
| Placement     | Row order inside the stats block: subscribers → **videos** → views.                                                                                                                             |
| Scope         | The video row renders only when `show_video_count?` is true; it lives inside the existing `show_stats?` block.                                                                                  |

## Phase index

- P0 — Add the opt-in video-count stat row

## P0 — Add the opt-in video-count stat row

- [x] T0.1 Add `videos_count_singular: "%{count} video"` + `videos_count_plural: "%{count} videos"` keys to `config/locales/pito/copy/en.yml`, immediately after `views_count_plural`. complexity: [low]
- [x] T0.2 Add `show_video_count:` keyword (default `false`) to `Pito::Channel::ItemComponent#initialize`, store as `@show_video_count`, and add a `show_video_count?` reader. complexity: [low]
- [x] T0.3 Add a `videos_count_label` method to `ItemComponent` that reads `channel.videos.count` and renders the singular/plural copy key (mirror `views_label`). complexity: [low]
- [x] T0.4 Insert a video-count stat row in `item_component.html.erb` between the subscribers row and the views row, wrapped in `<% if show_video_count? %>`, with classes mirroring the sibling stat rows (`pito-channel-item__stat--videos`). complexity: [low]
- [x] T0.5 Pass `show_video_count: true` to the `ItemComponent` render call in `list_component.html.erb`. complexity: [low]
- [x] T0.6 Update the `ItemComponent` class doc-comment: document the new `show_video_count:` kwarg in the kwargs list and note the videos row in the stats description. complexity: [low]
- [x] T0.7 Add specs to `spec/components/pito/channel/item_component_spec.rb`: singular (`1 video`), plural (`0 videos`, `N videos`), row absent without the kwarg, and row ordered between subs and views. complexity: [low]
- [-] T0.8 Commit: `Add opt-in video-count stat to channel card`. complexity: [manual]

## How to use this plan

On "go", execute P0 task-by-task (one Sonnet sub-agent per atomic task),
flipping checkboxes per transition, suite green throughout. Verify:
`bundle exec rspec` green, `bin/rubocop` clean, copy guard (1-or-50) green.
