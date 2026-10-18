# Nooklings roadmap

Updated: October 18, 2026

## Implemented

- [x] Five lifelike companions: Byte, Ripple, Biscuit, Miso, and Bao
- [x] Six expressions, species-specific care animations, sounds, and idle tricks
- [x] Individual needs, food, hydration, play, timed rest, and optional check-ins
- [x] Care dashboard, separate pet histories, and reduced-motion care
- [x] Nooklings app branding and illustrated companion guide
- [x] Drag-to-pin position and notch reset
- [x] Streaming chat, markdown, vision, and web citations
- [x] Persistent conversations, archive browser, and image sidecars
- [x] Settings, launch at login, and approximate session cost

## Code review improvements

- [x] Unique archives, explicit save errors, and write-failure recovery
- [x] Save prompts before requests and checkpoint interrupted replies
- [x] Preserve corrupt history before replacing it
- [x] Keychain storage with failure-aware legacy migration
- [x] Model-specific request options and Haiku 4.5 vision
- [x] Stop/cancel, bounded retries, and stale-callback protection
- [x] Require message_stop and exclude failed replies from API context
- [x] Capture request settings and final cumulative usage
- [x] Restrict generated links to web URLs and label main icon controls
- [x] Regression tests and macOS build/test/bundle workflow

## Next

- [ ] Rename the GitHub repository from `byte` to `nooklings` (requires repository settings access)
- [x] ChatGPT plan sign-in for the local app, live account model catalog, and provider switching
- [ ] Validate ChatGPT browser sign-in, Keychain, refresh, and streaming on macOS
- [ ] Obtain Anthropic approval before adding Claude subscription sign-in
- [ ] Global shortcut to open and focus chat
- [ ] Context budget, optional thread summary, and cost controls
- [ ] Check model availability; maintain capabilities and pricing together
- [ ] Developer ID signing, notarization, and repeatable distribution

## Following

- [ ] Image picker, missing-image recovery, and safe sidecar cleanup
- [ ] Per-display drag constraints and monitor-change testing
- [ ] Resizable chat panel and broader reduced-motion / VoiceOver validation
- [ ] Separate networking, persistence, pet simulation, and views
- [ ] Report login-item errors and handle requiresApproval consistently
- [ ] Test provider retry/continuation behavior and supported toolchains

See docs/CODE_REVIEW.md for evidence, validation limits, and acceptance criteria.
Existing model IDs were retained and need a live Anthropic availability check.
