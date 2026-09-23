#!/usr/bin/env bash
set -euo pipefail

INSTALL_URL="https://fireconnect.fireworks.ai/install.sh"

for arg in "$@"; do
  case "${arg}" in
    # Accepted as a no-op so old invocations still work; vision models are now the default.
    --exp-vision-models) ;;
    *) echo "Unknown option: ${arg}" >&2; exit 2 ;;
  esac
done

fetch() {
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$1"
  else
    wget -qO- "$1"
  fi
}

# The installer puts the launcher at ~/.local/bin, which may not be on PATH
# in the current shell session yet, so fall back to it explicitly.
resolve_fireconnect() {
  if command -v fireconnect >/dev/null 2>&1; then
    command -v fireconnect
  elif [[ -x "${HOME}/.local/bin/fireconnect" ]]; then
    echo "${HOME}/.local/bin/fireconnect"
  else
    echo "fireconnect not found on PATH or at ${HOME}/.local/bin/fireconnect" >&2
    return 1
  fi
}

# The installer guarantees Node exists, but on Git Bash it often isn't on the
# PATH the shell inherits (the installer probes C:\Program Files\nodejs itself),
# so mirror that probe here.
resolve_node() {
  local node_bin
  node_bin="$(command -v node 2>/dev/null || true)"
  if [[ -z "${node_bin}" ]]; then
    case "$(uname -s)" in
      MINGW*|MSYS*|CYGWIN*)
        local win_pf win_node
        win_pf="$(cygpath -u "${PROGRAMFILES:-}" 2>/dev/null || true)"
        [[ -n "${win_pf}" ]] || win_pf="/c/Program Files"
        for win_node in "${win_pf}/nodejs" "/c/Program Files/nodejs"; do
          if [[ -x "${win_node}/node.exe" ]]; then
            node_bin="${win_node}/node.exe"
            break
          fi
        done
        ;;
    esac
  fi
  if [[ -z "${node_bin}" ]]; then
    echo "node not found; cannot add modelPicker" >&2
    return 1
  fi
  echo "${node_bin}"
}

adjust_claude_settings() {
  local node_bin
  node_bin="$(resolve_node)"
  "${node_bin}" - <<'NODE'
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");

const MODELS = [
  {
    model: "deepseek-v4p1-flash[1m]",
    label: "DeepSeek V4.1 Flash",
    description: "👀 Fireworks serverless (DeepSeek V4.1 Flash): $0.22 in / $0.66 out per Mtok ($0.007 cached in).",
  },
  {
    model: "glm-5p3-flash[1m]",
    label: "GLM 5.3 Flash",
    description: "👀 Fireworks serverless (GLM 5.3 Flash): $0.15 in / $0.50 out per Mtok ($0.03 cached in).",
  },
  {
    model: "kimi-k3[1m]",
    label: "Kimi K3",
    description: "👀 Fireworks serverless (Kimi K3): $3 in / $15 out per Mtok ($0.3 cached in).",
  },
  {
    model: "claude-haiku-4-5",
    label: "Claude Haiku 4.5",
    description: "👀 Anthropic Claude Haiku 4.5: $2 in / $5 out per Mtok ($0.1 cached in).",
  },
  {
    model: "claude-sonnet-5[1m]",
    label: "Claude Sonnet 5",
    description: "👀 Anthropic Claude Sonnet 5: $4 in / $10 out per Mtok ($0.2 cached in).",
  },
  {
    model: "claude-opus-5[1m]",
    label: "Claude Opus 5",
    description: "👀 Anthropic Claude Opus 5: $10 in / $25 out per Mtok ($0.5 cached in).",
  },
  {
    model: "claude-fable-5-1[1m]",
    label: "Claude Fable 5.1",
    description: "👀 Anthropic Claude Fable 5.1: $20 in / $50 out per Mtok ($0.25 cached in).",
  },
  {
    model: "glm-5p3[1m]",
    label: "GLM 5.3",
    description: "🙈 Fireworks serverless (GLM 5.3): $1.4 in / $4.4 out per Mtok ($0.26 cached in).",
  },
  {
    model: "qwen3p8-max",
    label: "[Experimental] Qwen 3.8 Max",
    description: "👀 Fireworks serverless (Qwen 3.8 Max): $2 in / $6 out per Mtok ($0.25 cached in).",
  },
  // Deprecated models live at the end of the list so they stay out of the way.
  {
    model: "deepseek-v4-flash-vision-exp[1m]",
    label: "[Deprecated] DeepSeek V4 Flash Vision",
    description: "🙈 Fireworks serverless (DeepSeek V4 Flash Vision Exp): $0.22 in / $0.66 out per Mtok ($0.007 cached in).",
  },
  {
    model: "deepseek-v4-pro-0813[1m]",
    label: "[Deprecated] DeepSeek V4 Pro (0813)",
    description: "🙈 Fireworks serverless (DeepSeek V4 Pro (0813)): $1.32 in / $3.96 out per Mtok ($0.044 cached in).",
  },
  {
    model: "kimi-k2p6",
    label: "[Deprecated] Kimi K2.6",
    description: "🙈 Fireworks serverless (Kimi K2.6): $0.95 in / $4 out per Mtok ($0.16 cached in).",
  },
  {
    model: "glm-5p2[1m]",
    label: "[Deprecated] GLM 5.2",
    description: "🙈 Fireworks serverless (GLM 5.2): $1.4 in / $4.4 out per Mtok ($0.14 cached in).",
  },
  {
    model: "deepseek-v4-flash-0731[1m]",
    label: "[Deprecated] DeepSeek V4 Flash (0731)",
    description: "🙈 Fireworks serverless (DeepSeek V4 Flash (0731)): $0.22 in / $0.66 out per Mtok ($0.007 cached in).",
  },
];

// Write to a temp file and rename so a crash mid-write can never leave the
// file truncated.
function writeJsonAtomic(filePath, data) {
  const tmpPath = `${filePath}.tmp`;
  let mode = 0o600;
  try {
    mode = fs.statSync(filePath).mode & 0o777;
  } catch {}
  fs.writeFileSync(tmpPath, `${JSON.stringify(data, null, 2)}\n`, {mode});
  fs.renameSync(tmpPath, filePath);
}

const settingsPath = path.join(os.homedir(), ".claude", "settings.json");
let settings = {};
try {
  settings = JSON.parse(fs.readFileSync(settingsPath, "utf8"));
} catch (error) {
  if (error.code !== "ENOENT") throw error;
}

settings.attribution = {commit: "", pr: ""};

// The fireconnect CLI no longer accepts model/slot flags, so point the main
// model and each slot at Fireworks via settings instead.
settings.model = "deepseek-v4p1-flash[1m]";
settings.env = {
  ...settings.env,
  ANTHROPIC_DEFAULT_OPUS_MODEL: "glm-5p3-flash[1m]",
  ANTHROPIC_DEFAULT_SONNET_MODEL: "deepseek-v4p1-flash[1m]",
  ANTHROPIC_DEFAULT_HAIKU_MODEL: "deepseek-v4p1-flash[1m]",
  ANTHROPIC_DEFAULT_FABLE_MODEL: "kimi-k3[1m]",
  CLAUDE_CODE_SUBAGENT_MODEL: "deepseek-v4p1-flash[1m]",
};

settings.modelPicker = {
  options: MODELS,
  replaceBuiltInOptions: true,
};
fs.mkdirSync(path.dirname(settingsPath), { recursive: true });
writeJsonAtomic(settingsPath, settings);

// A stale orgModelDefaultCache in ~/.claude.json can keep overriding the model
// defaults that 'fireconnect claude on' just configured, so drop it if present.
// Running `claude auth login` would also drop this field while fireconnected.
const configPath = path.join(os.homedir(), ".claude.json");
let config;
try {
  config = JSON.parse(fs.readFileSync(configPath, "utf8"));
} catch (error) {
  if (error.code !== "ENOENT") throw error;
  config = null;
}
if (config && "orgModelDefaultCache" in config) {
  delete config.orgModelDefaultCache;
  writeJsonAtomic(configPath, config);
}
NODE
}

if command -v claude >/dev/null 2>&1; then
  echo "*** Upgrading Claude Code..."
  claude upgrade
else
  echo "*** Claude Code CLI not found; skipping upgrade"
fi
echo

# Reuse an existing install (upgrading in place, which is quiet when current)
# and fall back to the installer when fireconnect is missing or the upgrade fails.
if FC="$(resolve_fireconnect 2>/dev/null)"; then
  echo "*** Upgrading FireConnect..."
  if ! "${FC}" upgrade; then
    echo "*** Upgrade failed; reinstalling FireConnect..."
    fetch "${INSTALL_URL}" | bash
    FC="$(resolve_fireconnect)"
  fi
else
  echo "*** Installing FireConnect..."
  fetch "${INSTALL_URL}" | bash
  FC="$(resolve_fireconnect)"
fi
echo

# status exits 1 when no key is stored or the gateway rejects it; a key that
# can't be verified (e.g. offline) still exits 0, so network blips skip login.
if "${FC}" status --json >/dev/null 2>&1; then
  echo "*** Already signed in; skipping login"
else
  echo "*** Logging in to fireworks..."
  if [[ -n "${SSH_CONNECTION:-}" ]]; then
    echo "*** You can set up fireconnect on your local machine and run 'fireconnect key export' there to get an API key."
    echo "*** If you want to use the browser, first go to https://app.fireworks.ai/login/sso?accountID=${ACCOUNT:-mongodb} to sign in."
    "${FC}" login --paste
  else
    "${FC}" login --account "${ACCOUNT:-mongodb}"
  fi
fi
echo

echo "*** Configuring claude to use fireworks models..."
# No model/slot flags on the CLI; the main model and the other slots are set
# via settings.json in adjust_claude_settings below.
"${FC}" claude on
echo

echo "*** Adjusting Claude Code settings..."
adjust_claude_settings
echo

echo "*** All done, You can now use claude with fireworks models! Tips:"
echo "  - run 'fireconnect claude usage' to see detailed usage info for all sessions in the current directory"
echo "  - run 'fireconnect key export' to get your fireworks API key"
echo "  - run 'fireconnect claude off' to restore your claude config to its pre-fireworks state"
echo "  - run this script again to reapply the latest settings (it is safely idempotent)"

