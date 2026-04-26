# Step 5: Purge + Nav Overhaul — Testing

## Automated Tests

```bash
bundle exec rspec
# 43 examples, 0 failures
```

## Manual Verification

### 1. Browser (http://localhost:3000)

- Header shows: Pito logo (red P) · Channels · Videos · Settings (no text next to logo)
- Logo links to / (Dashboard)
- No "Dashboard", "Compare", "Production", "Notes", or "Sidekiq" in nav
- Footer shows © 2026 Pito
- Favicon is the Pito logo
- `/channels` works
- `/videos` works (placeholder)
- `/settings` works
- `/sidekiq` still works (requires basic auth, not linked from UI)

### 2. Confirm purged routes return 404

- `/compare` → 404
- `/productions` → 404
- `/notes` → 404

### 3. Console

```ruby
# Confirm tables are gone
ActiveRecord::Base.connection.tables
# Should NOT include "productions" or "notes"
```
