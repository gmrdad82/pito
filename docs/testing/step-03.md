# Step 3: Models + Migrations + Encrypted Attrs — Testing

## Automated Tests

```bash
bundle exec rspec spec/models/
# 29 examples, 0 failures
```

## Manual Verification

### 1. Check migrations ran

```bash
bin/rails db:migrate:status
# All migrations should show "up"
```

### 2. Console: model CRUD

```bash
bin/rails console
```

```ruby
# AppSetting
AppSetting.set("test_key", "test_value")
AppSetting.get("test_key")  # => "test_value"

# Channel (public)
ch = Channel.create!(youtube_channel_id: "UC_test_123", title: "Test Channel")
ch.owned?  # => false

# Channel (owned)
ch2 = Channel.create!(youtube_channel_id: "UC_mine_456", title: "My Channel", owned: true)
Channel.owned.count    # => 1
Channel.public_only.count  # => 1

# Video
v = Video.create!(channel: ch, youtube_video_id: "vid_abc", title: "Test Video")
ch.videos.count  # => 1

# VideoStat
VideoStat.create!(video: v, date: Date.today, views: 100, likes: 10)
v.video_stats.count  # => 1

# Production (no video)
p = Production.create!(title: "Next video idea", status: :idea)
p.idea?  # => true

# Note
n = Note.create!(title: "Remember this", kind: :todo)
n.todo?  # => true
```

### 3. Verify encryption

```ruby
# In console
setting = AppSetting.set("secret", "my_secret_value")
raw = AppSetting.connection.select_one("SELECT value FROM app_settings WHERE id = #{setting.id}")
raw["value"]  # Should NOT be "my_secret_value" (it's encrypted)
setting.reload.value  # => "my_secret_value" (decrypted via model)
```

### 4. Browser

Visit http://localhost:3000 — verify:
- "P" logo in top-left header
- Footer with "© 2026 Pito" at the bottom
- All nav links still work (Dashboard, Channels, etc.)

### 5. Cleanup test data

```ruby
[AppSetting, Channel, Video, VideoStat, Production, Note].each(&:destroy_all)
```
