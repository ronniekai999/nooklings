# Nooklings roadmap

Updated: October 26, 2026

## Implemented

- [x] Six lifelike baby companions: Niblet, Bubbles, Waffles, Mochi, Pebble, and Puddle
- [x] Six expressions, species-specific care animations, sounds, and idle tricks
- [x] Individual needs, food, hydration, play, timed rest, and optional check-ins
- [x] Care dashboard, separate pet histories, and reduced-motion care
- [x] Nooklings app branding and illustrated companion guide
- [x] Drag-to-pin position and notch reset
- [x] Streaming chat, markdown, vision, and web citations
- [x] Persistent conversations, archive browser, and image sidecars
- [x] Settings, launch at login, and approximate session cost

## Code review improvements

- [x] Migrate source-launch preferences into the stable bundle suite
- [x] Allow switching away from a protected damaged pet save
- [x] Restore the primary pet VoiceOver action and keyboard activation
- [x] Integrate joy consistently across offline intervals, sleep, and need floors

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

- [x] Rename the GitHub repository from `byte` to `nooklings`
- [x] ChatGPT plan sign-in for the local app, live account model catalog, and provider switching
- [ ] Validate ChatGPT browser sign-in, Keychain, refresh, and streaming on macOS
- [ ] Obtain Anthropic approval before adding Claude subscription sign-in
- [x] Configurable global shortcut to open and focus chat without capturing context
- [x] Context budget, reviewed local summary, Claude output/search caps, and a persistent daily spending estimate guard
- [x] Check Claude model availability; share capabilities, limits, dated prices, and unknown/stale-price handling
- [x] Prepare universal builds and a repeatable Developer ID/notarization workflow
- [ ] Add Apple credentials, produce the first signed release, and verify installed-app upgrades/Keychain identity

## Following

- [x] Image picker, background downsampling, missing-image recovery, and conservative sidecar cleanup
- [x] Per-display visible-frame constraints and geometry tests for separated/small/unplugged displays
- [ ] Validate real monitor changes and full-screen Spaces on installed macOS
- [x] Resizable chat panel, larger transcript text, reading-position preservation, and keyboard/VoiceOver actions
- [ ] Complete the installed-app Reduce Motion / VoiceOver matrix in docs/ACCESSIBILITY.md
- [x] Extract preferences, shortcut registration, geometry, model metadata, limits, and attachment helpers
- [ ] Continue separating streaming and conversation persistence from ByteModel
- [x] Report login-item errors and handle requiresApproval consistently
- [ ] Test provider retry/continuation behavior and supported toolchains

See docs/CODE_REVIEW.md for evidence, validation limits, and acceptance criteria.
Live account availability is checked in the app; CI uses provider mocks. See
docs/MODELS_AND_LIMITS.md for the dated pricing reference and API restrictions, and
docs/DISTRIBUTION.md for signing setup and upgrade acceptance criteria.
