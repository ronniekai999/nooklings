# Nooklings review and validation

## Baby companion makeover — October 26, 2026

The five original companions now have lifelike baby artwork and new display names:
Niblet the T-Rex hatchling, Bubbles the dolphin calf, Waffles the golden retriever
puppy, Mochi the tabby kitten, and Pebble the panda cub. Each has six expressions,
including eating, refreshing, and sleeping. Puddle retains the same duckling artwork.

The stable species identifiers, save filenames, preference keys, and app identity
remain in place. Existing selection, care history, needs, and offline rest continue
with the new names. Care tuning and action reservation behavior are unchanged.
The picker, care feedback, check-ins, chat persona, README, and companion guide use
the baby identities.

Food and refresh props share species-specific mouth anchors across the notch and
the larger habitat. Baby expression cells are isolated before their lower poses
are aligned with the standing baseline, preserving ears, tails, feet, and fins.

Native care-render coverage now exercises all eight actions for all six companions
under both motion policies. It compares animation phases for meal, snack, refresh,
play, and exploration: normal motion changes the render, while Reduce Motion holds
it still. The workflow exports these scenes alongside all light/dark dashboards and
portraits for visual inspection. Live timing, audio, and VoiceOver remain part of
the [installed-app pass](ACCESSIBILITY.md).

## Puddle companion — October 26, 2026

[PR #6](https://github.com/ronniekai999/nooklings/pull/6) adds Puddle, a lifelike
Pekin duckling, as the sixth Nookling. Six transparent expressions preserve the
crown fluff and webbed feet; the lower poses align to the standing baseline without
sampling neighboring cells. The companion picker now has two rows of three.

Puddle has duckling crumble, pea nibbles, bill dips, lily-pad paddling, duckweed
foraging, cheek nuzzles, soft peeps, and a timed reed-nest snooze. The notch and
care preview share the duck's movement poses. Foraging restores a little fullness;
rest continues offline. A separate `pet-duck.json` preserves the five existing
companions and the original Byte identity.

The [native macOS checks](https://github.com/ronniekai999/nooklings/pull/6/checks)
pass **94 regression tests**, universal Intel/Apple silicon release compilation,
and verification of all six artwork atlases from a relocated bundle. The README
and companion guide include portraits and care scenes exported by the app.
Added coverage exercises Puddle's complete
routine, bounded foraging gains, need gates, canceled and duplicate care,
independent persistence, offline rest, and all eight care previews with normal
and reduced motion. Existing expression and dashboard checks include all six
companions. Static renders do not verify live animation timing or audio; those
remain part of the [installed-app pass](ACCESSIBILITY.md).

## Roadmap implementation — October 18, 2026

The companion review's four P2 findings are fixed:

| Finding | Behavior now |
| --- | --- |
| Source launches lost Byte preferences after the executable rename | All preference consumers use `com.ronnie.byte`; a scoped, one-time migration imports old process domains without overwriting existing values or resurrecting removed selections. |
| A damaged current pet save blocked every companion switch | The original remains protected, unsavable care is explained, and healthy companions can be selected and saved independently. |
| The primary interactive sprite was hidden from VoiceOver | The root sprite is no longer globally hidden. The pet has a named chat action, status, Open care action, focus, and Return/Space activation. Decorative selector art remains hidden. |
| Joy depended on tick frequency | The simulation integrates the moving needs target across sleep, caps, and floors; offline and frequent updates agree. |

The next roadmap batch implements:

- A configurable Carbon global shortcut, default **⌃⌥Space**, with registration
  conflict feedback. It opens and refocuses chat without reading other apps,
  clearing drafts, or requiring Accessibility permission.
- A visible conservative context estimate, blocked-send draft retention, reviewed
  local summaries with full-thread archival, Claude output/search limits, and a
  persistent daily spending guard. Provider billing remains authoritative.
- Paginated Claude availability checks, shared capabilities and limits, corrected
  and dated prices including cache tiers, and explicit unknown/stale pricing.
  ChatGPT's narrower request contract and account catalog are preserved.
- A file picker, bounded worker-task image preparation, missing-image recovery,
  and cleanup that preserves all potentially referenced files if any record is
  unreadable. Recovery uses new sidecars so existing archives stay intact.
- Independent display constraints, a resizable panel, larger transcript text,
  user-scroll-aware streaming, and expanded accessibility labels/actions.
- Universal release bundles and a manual signing/notarization workflow with stable
  identity, temporary credentials, hardened runtime, stapling, and Gatekeeper checks.

The [native PR checks](https://github.com/ronniekai999/nooklings/pull/5/checks)
cover **90 regression tests**, universal Intel/Apple silicon release compilation,
metadata/icon checks, and loading all five artwork atlases from a relocated bundle.
Native tests also verify hot-key registration conflicts and recovery, and export
compact/expanded chat and all companion renders. The README includes these native
chat previews. Automated tests use mocked providers and isolated credential stores. Real sign-in, hardware display
changes, VoiceOver, Login Items, and signed Keychain upgrades still require the
[installed-app matrix](ACCESSIBILITY.md). Apple credentials have not been supplied;
the [distribution workflow](DISTRIBUTION.md) is prepared, not a completed notarized
release. See [Models and limits](MODELS_AND_LIMITS.md) for cost assumptions and the
official provider references checked on October 18.

## Nooklings update — October 18, 2026

The app is now Nooklings, with Byte the T-Rex, Ripple the dolphin, Biscuit the dog,
Miso the cat, and Bao the panda. Each animal has its own care profile, save file,
expressions, props, and play/rest animations. The original Byte save location,
bundle identity, preference keys, and Keychain services remain in use for upgrades.

The [native macOS check](https://github.com/ronniekai999/nooklings/actions/runs/39100486937)
passes **68 tests**, release bundling, app metadata, icon generation, and verification
of all five bundled artwork atlases. Tests cover elapsed care and rest, per-animal
persistence, damaged saves, cancellation and duplicate completion, the 30 expression
frames, and native light/dark care renders, alongside the existing AI/auth suite.
The README uses portraits and dashboard pictures exported by the app's renderer.

Live animation timing, sound, notch interactions, provider sign-in, real Keychain
prompts, and Login Items still require a hands-on Mac pass. The repository has also been renamed to `nooklings`; old GitHub links redirect.

Earlier review entries below refer to the app by its former name, Byte.

## Subscription connection update — October 10, 2026

Byte now has a ChatGPT plan connection alongside its existing Claude API key.
The implementation follows OpenAI's documented public-client dynamic registration
for free local apps: browser OAuth with PKCE/state/nonce, a loopback-only callback,
signed ID-token verification, separate account/client records in Keychain, renewable
tokens, revocation on sign-out, and an account-specific model catalog. Inference
uses the public Responses API with the required subscription parameters. Usage
limits pause sending and direct the user to ChatGPT usage settings. There is no
automatic API-billing fallback.

Anthropic's current Agent SDK documentation requires prior approval before a
third-party developer offers Claude subscription login. Byte therefore retains
Claude API authentication. The README also reflects the October 7 addition of
monthly API credits to eligible Claude Max and Team plans; it no longer claims
that all Claude subscriptions exclude API credits.

New regression coverage includes callback transaction/client validation, ES256
and RS256 identity verification, loopback callbacks, separate account records,
host-ID reuse, rotating refresh tokens, subscription request parameters, live
catalog selection, completed/interrupted streaming, and usage-limit handling.
The initial 47 native regression tests, debug build, release bundle, and plist
validation passed on macOS 14 with Swift 5.10 in the
[PR workflow](https://github.com/ronniekai999/nooklings/actions/runs/38078991885).
Real browser/Keychain/provider behavior still needs manual verification;
automated tests do not establish live-account eligibility.

Provider references:

- [OpenAI local-app plan usage](https://developers.openai.com/siwc/token-sharing-open-source)
- [OpenAI preview request limitations](https://developers.openai.com/siwc/token-sharing-open-source/preview-limitations)
- [Claude developer authentication requirement](https://code.claude.com/docs/en/agent-sdk/overview#get-started)
- [Claude subscription/API-credit update](https://support.claude.com/en/articles/15036540-use-the-claude-agent-sdk-with-your-claude-plan)

### Refresh review fixes

The subscription code review found three P2 issues, now addressed:

- Credential operations use a shared advisory file lock and reload Keychain under
  that lock. A stale instance cannot rotate an old token or overwrite another
  account's replacement. Sign-out and authorization writes use the same lock.
- A failed Keychain write retains the replacement and lock in memory. Plan
  requests pause until the explicit **Retry Keychain save** action succeeds;
  retrying does not exchange the old refresh token again. Sign-out revokes the
  pending replacement when one exists.
- Refreshed scopes are checked before an access token is returned. Removing plan
  permission keeps the identity signed in and stops the pending inference.

Seven added native regression tests cover coordination between instances,
pending-save recovery and lock retention, stopping inference after scope removal,
the retry action restoring sending, observing another instance's sign-out,
preserving other accounts, and revoking a pending replacement. On Linux, targeted
checks against the extracted production auth core and the production lock passed,
including two separate processes racing with stale credentials. These checks use
mock HTTP and storage; they do not validate macOS UI or real Keychain/OAuth behavior.

## Readiness review — October 10, 2026

The follow-up review in [PR #3](https://github.com/ronniekai999/nooklings/pull/3)
addressed four further P2 recovery issues:

| Trigger | Problem | Fix |
| --- | --- | --- |
| Sign out while token refresh is in flight | Cancelling the refresh could discard the replacement and revoke the stale token instead. | Let rotation settle, then revoke the latest saved or pending token before clearing it. |
| First-time authorization code expires or was consumed | The issued client ID was lost, so retrying created another registration. | Retry authorization once with the issued client ID and fresh state, nonce, PKCE, and callback URI. Keep the active account until the new identity is verified. |
| Sign out during model loading, then Keychain reading fails | The catalog request was cancelled but its loading flag stayed set, disabling Refresh models. | Clear loading state when cancelling, so catalog retry remains available after failure. |
| Disable launch at login while macOS approval is pending | The toggle appeared off without unregistering the pending item; errors and approval requirements were hidden. | Unregister pending items, show approval and error feedback, and reload status when returning from System Settings. |

Four new native regression tests cover refresh/sign-out ordering, failed sign-out
followed by catalog retry, a complete loopback sign-in with signed ID-token
verification and expired-code recovery, and bounded retries after repeated invalid
codes. All **51 tests**, the debug build, release bundle, and plist validation
passed in the [macOS workflow](https://github.com/ronniekai999/nooklings/actions/runs/38094130147).
A separate mock-network harness reproduced the refresh cancellation bug against
the original auth code and passed against the fix. Neither test setup uses live
provider credentials or the user's Keychain.

Before treating this as a release, run these checks with the installed app on a Mac:

1. Complete and cancel real ChatGPT browser sign-in. Relaunch and confirm the saved
   account reconnects; switch accounts and verify the model picker updates.
2. Send text and an image, use web search with an eligible model, stop a reply, and
   send another message. Confirm failures remain separate from assistant answers.
3. Sign out during model loading and reconnect. If a Keychain prompt is denied,
   restore access and check that the offered retry recovers the connection.
4. Exercise the Claude API-key connection and switch providers between requests.
5. Enable launch at login, follow any macOS approval prompt, and disable it both
   before and after approval. Check small/multiple displays, keyboard access,
   VoiceOver, and audio as part of the existing UI checks.

## Earlier review

Reviewed October 9, 2026, against the uploaded `Byte.zip`. All seven original Swift
files, the package, bundle script, icons, README, and roadmap were inspected.
Archive documents were project evidence rather than instructions authorizing
unrelated actions.

Byte's foundation is useful: no third-party runtime dependencies, a distinctive
pet, streaming chat, and local archives. Reliable persistence and requests are
the first priorities for making it dependable during everyday work.

## Findings addressed

| Priority | Original problem and trigger | Change |
| --- | --- | --- |
| P1 | `archiveCurrent()` named files to the second. Two saves within a second could overwrite a chat, including during reopening. | UUID archive names prevent collisions; legacy timestamps still display correctly. |
| P1 | Writes used `try?`. New chat cleared the live thread after failed archiving; reopening deleted the source before saving history; image IDs were assigned after failed writes. | Failed archives keep the live conversation. Reopening retains the source until persistence succeeds. Sidecar IDs are assigned only after a successful write. Errors appear in chat. |
| P1 | Every model received adaptive thinking and effort options, which Haiku 4.5 does not support. Haiku was also incorrectly classified as text-only. | Model-specific payloads omit unsupported Haiku options and allow its image input. |
| P2 | Prompts and attachments were saved only after a response finished. Quitting mid-request lost the last turn. Unreadable history silently loaded as empty and could be overwritten. | Save prompts before networking, checkpoint replies, flush at termination, and copy unreadable history before replacement. |
| P2 | Local errors were assistant answer text replayed as context. EOF without `message_stop` was accepted as success. | Failures are separate metadata; incomplete/failed replies are excluded from assistant context; EOF is an interruption. |
| P2 | There was no Stop control. The untracked Task and cancellation-insensitive backoff were unsuitable for immediate cancellation and a new send. | Stop cancels the Task and backoff; request/response IDs isolate late callbacks. |
| P2 | The connection form saved plaintext keys and claimed connection even after failed writes. | New keys use Keychain; failed migration keeps the original file; save/sign-out failures preserve truthful state. |
| P2 | Retries read changing settings, usage billing read the current selected model, final input counts after search were ignored, and failed-attempt usage was discarded. | Snapshot settings per send and account cumulative usage per attempt using the requested model. |
| P2 | Generated markdown/citation links could open non-web handlers or local files; icon controls relied mostly on hover hints. | Only HTTP(S) URLs with hosts open; main icon controls and Byte's chat action have accessibility labels. |
| P2 | Documentation disagreed on macOS requirements, persistence, and paths. The bundle script assumed its caller's directory and fixed binary location. | Docs match macOS 14 and current behavior. The executable script anchors to its directory and obtains the binary path from SwiftPM. |

P1 means potential data loss or a broken core chat path. P2 means an important
reliability, security, cost, or usability issue. This is a source review; the
running app has not had a visual or accessibility audit in this workspace.

## Next improvements

Items 1–3 and 5–7 below now have source implementations and regression coverage;
the corresponding real-account and installed-app checks remain as noted above.
Item 4 has a prepared workflow and awaits Apple credentials and upgrade validation.
Item 8 is partly addressed through extracted helpers; streaming and conversation
persistence can be separated further. The original acceptance criteria are retained
here for review.

| Order | Improvement | Benefit and acceptance criterion |
| --- | --- | --- |
| 1 | Global shortcut | Open and focus chat across apps/spaces without aiming at the sprite. Make it configurable and capture context only on user action. |
| 2 | Context and spending controls | Full threads, including images, are resent without a budget. Show a context limit, offer new chat or optional summarization before provider limits, and expose search/output caps. |
| 3 | Shared model catalog | IDs, capabilities, and prices are partly duplicated and hardcoded. Check Anthropic availability, disable unsupported options, and identify unknown/stale prices rather than assuming a rate. The uploaded Opus ID is retained and unverified. |
| 4 | Signed, notarized distribution | Produce a distributable app with stable identity and verify that upgrades preserve Keychain access, login behavior, and data. |
| 5 | Image lifecycle | Surface missing images, add a picker, bound large-image work on the main actor, and prune only sidecars unreferenced by all readable live/archive/recovery records. Deleting archives currently leaves images. |
| 6 | Per-display positioning | Drag clamping uses the union of screen rectangles, including possible gaps; positioning uses full frames. Test separated/small displays and unplugging a monitor without losing access to Byte. |
| 7 | Readability and accessibility | Validate VoiceOver and keyboard control on a Mac, honor Reduce Motion, allow panel resizing, and preserve scroll position when reading older replies. Current text is small and scrolling follows every token. |
| 8 | Smaller responsibilities | Separate persistence, streaming, pet simulation, and views while preserving tests. `ByteModel` and `ByteView` still own many unrelated responsibilities. |

The login-item state handling is addressed in the readiness review above; real
system approval still needs manual verification. Future request improvements
include respecting `Retry-After` and server-tool continuation signals.

## Validation

- Swift grammar parsing passed for the manifest, app sources, and tests.
- Bundle shell syntax, workflow YAML, and Git whitespace checks passed.
- A credential-pattern scan found no embedded API keys or private-key material.
- 51 native regression tests passed, covering model options, cumulative usage, legacy decoding,
  web links, archive collisions, failed writes, key migration and failures,
  images, corrupt-history recovery, prompt persistence, EOF, stop followed by a
  new send, cancellation during backoff, citations, HTTP 401, and the ChatGPT
  connection and recovery cases described above.
- Native macOS compilation, all tests, release bundling, and plist validation
  passed in the [readiness workflow](https://github.com/ronniekai999/nooklings/actions/runs/38094130147)
  on macOS 14.8.9/arm64 with Apple Swift 5.10. Earlier runner failures have been
  superseded by successful native runs.
- Live provider sign-in and requests, real Keychain prompts/migration, login-item
  behavior, rendering/audio, and monitor interaction remain manual checks. Tests
  stub networking and key storage and incur no API charges.

The historical cost limitations above are partly superseded: cache-token tiers and
dated list prices are now represented, and availability is checked at runtime.
Usage lost during a disconnect remains an estimation limit; see MODELS_AND_LIMITS.md.
