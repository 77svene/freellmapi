# free-claude: one-command Claude Code on free models

`./free-claude.sh` boots a private FreeLLMAPI gateway on `127.0.0.1`, seeds your
free provider keys, fetches the unified key, and launches Claude Code with the
gateway injected into its environment. Nothing is written to `~/.claude`.

```bash
npm i -g @anthropic-ai/claude-code          # once
mkdir -p ~/.free-claude && cat > ~/.free-claude/keys.env <<'K'
GROQ_API_KEY=gsk_...
GEMINI_API_KEY=AIza...
OPENROUTER_API_KEY=sk-or-...
K
./free-claude.sh                            # interactive
./free-claude.sh -- -p "explain this repo"  # args after -- go to claude
./free-claude.sh --status                   # gateway URL + unified key
./free-claude.sh --stop                     # stop the background gateway
```

Keys: `GROQ_API_KEY`, `GEMINI_API_KEY`/`GOOGLE_API_KEY`, `OPENROUTER_API_KEY`,
`CEREBRAS_API_KEY`, `MISTRAL_API_KEY`, `NVIDIA_API_KEY`, `SAMBANOVA_API_KEY`,
`COHERE_API_KEY`, `ZHIPU_API_KEY`, `HF_TOKEN` (env or `keys.env`). Keys are
applied when the gateway starts; after editing them run `--stop` first. Other
providers: dashboard at the gateway URL → Keys (login is in
`~/.free-claude/state.env`).

Env overrides: `FREE_CLAUDE_HOME` (state dir, default `~/.free-claude`),
`FREE_CLAUDE_PORT` (default `3001`).

`claude-opus-*` / `claude-sonnet-*` / `claude-haiku-*` requests are mapped to
free models per the Claude model mapping on the Keys page.
