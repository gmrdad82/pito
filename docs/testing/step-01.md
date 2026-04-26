# Testing — Step 1: Rails App Foundation

## Automated

```bash
bundle exec rspec
# Expected: 0 examples, 0 failures (no specs yet, but framework loads clean)
```

## Manual Verification

### 1. Ruby version

```bash
ruby -v
# Expected: ruby 3.4.9
```

### 2. Rails boots

```bash
bundle exec rails runner "puts Rails.version"
# Expected: 8.1.3
```

### 3. Docker services start

```bash
docker compose up -d
docker compose ps
# Expected: mysql and redis both show "healthy"
```

### 4. Database setup

First, configure credentials (if not done yet):

```bash
EDITOR=vim rails credentials:edit
```

Add:

```yaml
mysql:
  development:
    database: pito_development
    username: root
    password: ""
  test:
    database: pito_test
    username: root
    password: ""
```

Then:

```bash
bin/rails db:create
bin/rails db:migrate
# Expected: no errors (no migrations yet, but DB should be created)
```

### 5. App starts

```bash
bin/dev
# Expected: Puma starts on port 3000, Sidekiq starts, Tailwind watcher starts
```

### 6. Browser checks

- http://localhost:3000/up — should return 200 (green health check)
- http://localhost:3000/sidekiq — should show Sidekiq Web dashboard

### 7. RSpec

```bash
bundle exec rspec
# Expected: 0 examples, 0 failures
```

### 8. RuboCop

```bash
bundle exec rubocop
# Note: may have some offenses from generated Rails code — that's expected at this stage
```
