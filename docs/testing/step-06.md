# Step 6: Visual Baseline — Testing

## Automated
```bash
bundle exec rspec   # 43 examples, 0 failures
bundle exec rubocop # 53 files, no offenses
```

## Manual (Browser)

1. Visit http://localhost:3000 — verify Verdana font, 12px size, compact spacing
2. Header: Pito.png logo aligned with nav text, 32px fixed bar, `[ Channels ] · [ Videos ] · [ Settings ]`
3. Nav links: underline only on text, not on brackets or spaces; bold for current page
4. Visit /settings — form constrained to ~480px, not full width
5. Submit button shows `[ save ]` in bold lowercase, no border/background, turns blue on hover
6. Footer: "© 2026 Pito. All rights reserved." on left, "Version 0.0.1.alpha" on right
7. Flash notices: save settings → green notice bar appears
8. Resize window: layout stays sensible, no horizontal overflow
