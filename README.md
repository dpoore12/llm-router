# LLM Router

One endpoint on your own server that routes AI work to the cheapest model
that can handle it, and logs the cost of every request.

| Tier you ask for | What runs it | Roughly |
|---|---|---|
| `cheap` | DeepSeek V4 Flash (GLM FlashX fallback) | ~$0.14 / 1M input tokens |
| `standard` | DeepSeek V4 Pro (GLM-5 fallback) | ~$0.44 / 1M input tokens |
| `heavy` | Claude Sonnet (needs Anthropic key, else degrades to `standard`) | Claude pricing |
| `ping` | mock — for testing, costs nothing | free |

Claude model names are aliased too (haiku→cheap, sonnet→standard, opus→heavy),
so tools that speak "Claude" work without changes.

## Install (once, on the box)

```bash
git clone https://github.com/dpoore12/llm-router /opt/llm-router
cd /opt/llm-router && bash bootstrap.sh
```

You'll be asked to paste:
1. **DeepSeek API key** (required) — platform.deepseek.com, pay-as-you-go
2. **Z.AI key** (optional) — vendor fallback
3. **Anthropic key** (optional) — enables the `heavy` tier

Keys live in `/etc/llm-router.env` (root-only). Never paste them in chat.
The script prints a **router master key** — that's the single credential
every client uses.

## Use it

OpenAI-style (any tool, any language):

```bash
curl https://llm.5-161-59-25.sslip.io/v1/chat/completions \
  -H "Authorization: Bearer <ROUTER_MASTER_KEY>" \
  -H "Content-Type: application/json" \
  -d '{"model":"cheap","messages":[{"role":"user","content":"hello"}]}'
```

Claude Code (in `~/.claude/settings.json` env or shell profile):

```bash
export ANTHROPIC_BASE_URL=https://llm.5-161-59-25.sslip.io
export ANTHROPIC_AUTH_TOKEN=<ROUTER_MASTER_KEY>
export ANTHROPIC_MODEL=standard
export ANTHROPIC_SMALL_FAST_MODEL=cheap
```

Perplexity Computer: save the master key as a custom credential for host
`llm.5-161-59-25.sslip.io`, then it can push bulk generation through the
router instead of burning credits on volume output.

## Watch the money

```bash
llm-router-stats        # per-day, per-tier spend, last 30 days
llm-router-stats --all
```

## Operations

```bash
systemctl status llm-router
journalctl -u llm-router -f
systemctl restart llm-router      # after editing config.yaml
```

- Service runs on `127.0.0.1:4300`; Caddy publishes it at
  `https://llm.5-161-59-25.sslip.io` (set `ROUTER_HOSTNAME` before running
  bootstrap to use your own domain).
- Memory-capped at 900M so it can never starve the BFR engine.
- Re-running `bootstrap.sh` upgrades LiteLLM and keeps your keys.
