#!/usr/bin/env bash
# free-claude — run Claude Code against FreeLLMAPI's free model pool.
#
#   ./free-claude.sh                 interactive Claude Code
#   ./free-claude.sh -- -p "hello"   anything after -- goes to `claude`
#   ./free-claude.sh --stop          stop the background gateway
#   ./free-claude.sh --status        show gateway state + unified key
#
# Provider keys (all free tiers) are read from the environment or from
# $FREE_CLAUDE_HOME/keys.env, e.g.  GROQ_API_KEY=gsk_...
# Supported: GROQ_API_KEY GEMINI_API_KEY (or GOOGLE_API_KEY) OPENROUTER_API_KEY
#            CEREBRAS_API_KEY MISTRAL_API_KEY NVIDIA_API_KEY SAMBANOVA_API_KEY
#            COHERE_API_KEY ZHIPU_API_KEY HF_TOKEN
# More providers: open the dashboard (http://localhost:$PORT) -> Keys.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOME_DIR="${FREE_CLAUDE_HOME:-$HOME/.free-claude}"
PORT="${FREE_CLAUDE_PORT:-3001}"
URL="http://127.0.0.1:$PORT"
mkdir -p "$HOME_DIR" && chmod 700 "$HOME_DIR"
STATE="$HOME_DIR/state.env" PID_FILE="$HOME_DIR/server.pid" LOG="$HOME_DIR/server.log"

die() { echo "free-claude: $*" >&2; exit 1; }
up() { curl -s -o /dev/null -m 2 "$URL/" 2>/dev/null; }

case "${1:-}" in
  --stop)
    [[ -f "$PID_FILE" ]] && kill "$(cat "$PID_FILE")" 2>/dev/null && echo "stopped" || echo "not running"
    rm -f "$PID_FILE"; exit 0 ;;
  --status|"") ;;
  --) ;;
  *) die "unknown option '$1' (pass claude args after --)" ;;
esac

command -v node >/dev/null || die "Node.js >= 20.18 required"
command -v claude >/dev/null || die "Claude Code not found: npm i -g @anthropic-ai/claude-code"

# 1. One-time secrets: encryption key + local admin login (never leave this dir).
if [[ ! -f "$STATE" ]]; then
  umask 077
  cat > "$STATE" <<EOF
ENCRYPTION_KEY=$(node -e 'console.log(require("crypto").randomBytes(32).toString("hex"))')
ADMIN_EMAIL=local@free-claude.local
ADMIN_PASSWORD=$(node -e 'console.log(require("crypto").randomBytes(18).toString("base64url"))')
EOF
fi
# shellcheck disable=SC1090
set -a; source "$STATE"; set +a
[[ -f "$HOME_DIR/keys.env" ]] && set -a && source "$HOME_DIR/keys.env" && set +a

# 2. Dependencies.
[[ -d "$REPO/node_modules" ]] || (cd "$REPO" && npm ci --no-audit --no-fund)

# 3. Start the gateway in the background unless it is already up.
if ! up; then
  CONFIG_JSON="$(node -e '
    const e = process.env, map = {
      groq: e.GROQ_API_KEY, google: e.GEMINI_API_KEY || e.GOOGLE_API_KEY,
      openrouter: e.OPENROUTER_API_KEY, cerebras: e.CEREBRAS_API_KEY,
      mistral: e.MISTRAL_API_KEY, nvidia: e.NVIDIA_API_KEY,
      sambanova: e.SAMBANOVA_API_KEY, cohere: e.COHERE_API_KEY,
      zhipu: e.ZHIPU_API_KEY, huggingface: e.HF_TOKEN };
    const keys = Object.entries(map).filter(([, k]) => k)
      .map(([platform, key]) => ({ platform, key, label: "free-claude" }));
    console.log(JSON.stringify({ admin: { email: e.ADMIN_EMAIL, password: e.ADMIN_PASSWORD }, keys }));
  ')"
  echo "free-claude: starting gateway on $URL (log: $LOG)" >&2
  (cd "$REPO" && ENCRYPTION_KEY="$ENCRYPTION_KEY" PORT="$PORT" HOST=127.0.0.1 \
     FREEAPI_DB_PATH="$HOME_DIR/freellmapi.db" FREEAPI_CONFIG_JSON="$CONFIG_JSON" \
     nohup "$REPO/node_modules/.bin/tsx" server/src/index.ts >"$LOG" 2>&1 & echo $! >"$PID_FILE")
  for _ in $(seq 1 90); do up && break; sleep 1; done
  up || { tail -20 "$LOG" >&2; die "gateway failed to start"; }
fi

# 4. Log in locally and fetch the unified key.
TOKEN="$(curl -s -XPOST "$URL/api/auth/login" -H 'content-type: application/json' \
  -d "{\"email\":\"$ADMIN_EMAIL\",\"password\":\"$ADMIN_PASSWORD\"}" \
  | node -pe 'JSON.parse(require("fs").readFileSync(0)).token || ""')"
[[ -n "$TOKEN" && "$TOKEN" != undefined ]] || die "login failed — is another FreeLLMAPI on port $PORT? set FREE_CLAUDE_PORT"
KEY="$(curl -s "$URL/api/settings/api-key" -H "Authorization: Bearer $TOKEN" \
  | node -pe 'JSON.parse(require("fs").readFileSync(0)).apiKey')"

if [[ "${1:-}" == "--status" ]]; then
  echo "gateway:   $URL (dashboard login: $ADMIN_EMAIL / see $STATE)"
  echo "key:       $KEY"
  exit 0
fi

# 5. Launch Claude Code with the gateway injected (no files written to ~/.claude).
[[ "${1:-}" == "--" ]] && shift
exec "$REPO/node_modules/.bin/tsx" "$REPO/cli/src/index.ts" launch --url "$URL" --api-key "$KEY" -- "$@"
