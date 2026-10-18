# Desktop validation

Automated native tests exercise focus requests, shortcut persistence, independent
display constraints, offline care, and chat/care rendering. They do not establish
real VoiceOver behavior, global-shortcut conflicts, or hardware monitor behavior.
The following installed-app pass remains necessary on a Mac.

| Scenario | Acceptance |
| --- | --- |
| VoiceOver, all five companions | The pet is discoverable by name and status, with a chat action and named Open care action. Decorative selector art is silent. |
| Care dashboard | Names, selected companion, needs percentages, unavailable-action reasons, rest progress, and care buttons are announced. Keyboard navigation reaches every action. |
| Chat keyboard access | The global shortcut opens chat from another app/Space and focuses the composer. Repeating it refocuses without closing or losing a draft. Tab reaches Settings, Saved chats, New chat, image controls, Send/Stop, and Resize chat. |
| Shortcut recording | Change the key combination, restart, and verify it persists. Esc cancels recording. An unmodified key is rejected; a conflicting registration reports an error and retains the previous shortcut. Disabling unregisters it. |
| Missing image | VoiceOver announces Image unavailable. Locate image and Remove attachment have distinct labels; a failed restore leaves the recovery controls available. |
| Summary and spending | Summary editor has a label and cancel/default keyboard actions. Limits and visible warnings can be reached and read. Unsaved drafts survive blocked sends. |
| Reading older replies | Scroll upward during a long stream. New tokens preserve the current position; Jump to latest resumes following. Repeat with wheel, trackpad, scrollbar, and VoiceOver scrolling. |
| Reduce Motion | Toggle while open. Idle tricks stop; care remains usable without large movement. Window and transcript animations are suppressed. |
| Resizing | Drag edges or use Resize chat → Larger/Smaller. Transcript grows, controls remain reachable, and size survives closing/reopening and relaunch. |
| Displays | Drag between separated displays and across menu/Dock edges. Unplug the pinned display. Open on a small display and a notched display, including a full-screen Space; the whole panel remains on a real visible display. |
| Release upgrade | Repeat with the signed installed bundle. Verify launch at login and real Keychain prompts separately; see DISTRIBUTION.md. |

Record macOS version, display arrangements, VoiceOver settings, and any exceptions
alongside the release's verification record. Avoid marking this matrix passed based
only on source labels or screenshots.
