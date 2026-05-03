# Tools

Application-level tools that work across all channels. Code lives in `scripts/`.

## Planned

- YouTube Data API integration (Ruby)
- Analytics dashboard
- Cross-channel performance views

## Principles

- Tools are channel-agnostic — they read/display data, they don't make style or
  content decisions
- Channel-specific context stays in `docs/channels/<channel>/`
- Tools config and specs go here; code goes in `scripts/`
