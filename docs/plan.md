# Build Plan

## Steps

- [x] **Step 1:** Rails app foundation — Ruby 3.4.9, Rails 8.1.3, all gems, database.yml, docker-compose.yml, .env, bin/dev, Sidekiq + Redis, RSpec
- [x] **Step 2:** Craigslist-style layout + top nav + Sidekiq Web with auth
- [x] **Step 3:** Models + migrations + encrypted attributes + factories + model specs
- [ ] **Step 4:** Settings page for OAuth credentials (AppSetting CRUD) + request specs
- [ ] **Step 5:** OAuth flow + Channels connect/disconnect + service specs with WebMock
- [ ] **Step 6:** SyncChannelJob + SyncVideoStatsJob end-to-end + job specs
- [ ] **Step 7:** Channel show + Video show pages
- [ ] **Step 8:** Charts on Video show (Chartkick + Groupdate)
- [ ] **Step 9:** Compare page — pick 2+ videos, side-by-side stats
- [ ] **Step 10:** Production CRUD + linking to videos
- [ ] **Step 11:** Notes CRUD (bare CRUD, title/body/kind)
- [ ] **Step 12:** sidekiq-cron schedule + polish
