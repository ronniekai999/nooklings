# Models, context, and spending

Provider documentation checked **October 18, 2026**. Account eligibility is verified
at runtime with the user's credentials; repository tests use mock responses.

## Catalogs and capabilities

Claude uses paginated `GET /v1/models` with the configured API key. **Check availability**
refreshes the list, excludes retired models, and records when it was checked.
An unavailable saved selection is preserved and sending pauses until the user chooses
a returned model. A network failure never silently chooses a different model.
The app checks on startup and after saving a key. Before a successful check, the
saved model remains visible as unverified; documented fallback metadata is available
for the original Sonnet 4.6, Opus 4.8, and Haiku 4.5 models.

`ModelCatalog.swift` is the common source for request features, Settings, context
windows, and pricing. Live capabilities override reference capabilities, including
explicitly disabled features. Unknown models get no guessed image/search/thinking
support or prices. Effort choices come from supported API values. The local limits
are also clamped to returned input/output limits.

ChatGPT retains the selected account's live `/v1/models` catalog, display ordering,
and model slugs. Its public plan route does not document the same capability schema
as Claude; image and search acceptance remain subject to model/account policy.
No API-key billing fallback is used. `max_output_tokens` and `max_tool_calls` are
unsupported on this route and are deliberately omitted. Settings explains that
output/search caps apply to Claude and links to ChatGPT's plan/credit usage controls.

## Price reference

Standard first-party Claude API USD per million tokens, excluding optional tool use:

| Model ID | Input | Output | Cache read |
| --- | ---: | ---: | ---: |
| `claude-sonnet-4-6` | $3 | $15 | $0.30 |
| `claude-opus-4-8` | $5 | $25 | $0.50 |
| `claude-haiku-4-5-20251001` | $1 | $5 | $0.10 |
| `claude-opus-5-5` | $4 | $20 | $0.20 |
| `claude-sonnet-5-5` | $2 | $10 | $0.10 |
| `claude-haiku-5-5` | $0.10 | $0.50 | $0.01 |

Haiku 5.5 rates multiply by five when total input exceeds 100,000 tokens.
Five-minute cache writes use 1.25× input pricing; one-hour writes use 2×. Usage
accounting includes separately reported cache reads/writes and cumulative search
usage. Search costs $0.01 per request, plus tokens. The old Opus 4.8 estimate of
$15/$75 was incorrect and is now $5/$25. Prices become explicitly stale after
90 days; unknown/stale prices never fall back to Sonnet prices.

These are dated list prices, not an automatically refreshed billing feed. Other
models can be discovered without a known price. Refreshing availability does not
reset the pricing verification date. Update the reference and this document together
when rechecking the provider's price list.

## Context and local spending guard

- **Thread context:** defaults to 32,000 estimated input tokens. The estimate includes
  instructions, the draft, eligible history, message overhead, and an 8,192-token
  reserve per image. Text uses a conservative byte-based estimate. It is not the
  provider tokenizer; unusual images/tool results can still differ.
- **Reply output:** Claude defaults to 2,048 tokens, configurable from 256–16,384.
- **Searches:** Claude defaults to three, configurable from zero–ten. Zero disables
  the tool, even if the Web search preference is on.
- **Daily API guard:** off by default (`$0`). When set, pauses sends and retries if
  the tracked estimate plus the proposed output/search reserve would exceed it.
  The ledger survives restarts and provider changes, resetting at UTC midnight.
  Unknown prices or incomplete pricing records pause sending while this guard is on.

The spending guard is local and approximate. Search-result tokens, unreported usage
after disconnects, concurrent app instances, and provider adjustments can exceed an
estimate. Use the provider's account controls for an enforced billing limit. ChatGPT
displays reported tokens, not an invented per-token dollar estimate.

When context is too large, sending leaves the draft/attachments intact. **New chat**
archives the full thread. **Summary…** offers local excerpts to edit into a concise
summary; it makes no summarization API request and has no AI cost. Confirming saves
the full original first, seeds the new thread with the reviewed text, and keeps the
unsent draft. Images remain with the full archive. No hidden truncation is performed.

References: [Claude model discovery](https://platform.claude.com/docs/en/api/models/list),
[Claude pricing](https://platform.claude.com/docs/en/about-claude/pricing),
[ChatGPT model discovery](https://developers.openai.com/siwc/token-sharing-open-source/models-and-inference),
[ChatGPT request restrictions](https://developers.openai.com/siwc/token-sharing-open-source/preview-limitations).
