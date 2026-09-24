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

# Drop a launcher that re-runs this script, so machines can self-update
# without keeping a local copy around.
install_updater() {
  local updater_dir="${HOME}/.local/bin"
  local updater="${updater_dir}/update-fireclaude"
  mkdir -p "${updater_dir}"
  cat > "${updater}" <<'EOF'
#!/usr/bin/env bash
exec bash <(curl -fsSL https://raw.githubusercontent.com/mongodb/afterburner/main/setup-fireconnect.sh) "$@"
EOF
  chmod +x "${updater}"
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
    description: "👀 Fireworks: cached $0.007 · in  $0.22 · out  $0.66",
  },
  {
    model: "glm-5p3-flash[1m]",
    label: "GLM 5.3 Flash",
    description: "👀 Fireworks: cached $0.03  · in  $0.15 · out  $0.50",
  },
  {
    model: "claude-haiku-4-5",
    label: "Claude Haiku 4.5",
    description: "👀 Anthropic: cached $0.10  · in  $2    · out  $5",
  },
  {
    model: "claude-sonnet-5[1m]",
    label: "Claude Sonnet 5",
    description: "👀 Anthropic: cached $0.20  · in  $4    · out $10",
  },
  {
    model: "claude-opus-5-5[1m]",
    label: "Claude Opus 5.5",
    description: "👀 Anthropic: cached $0.20  · in  $8    · out $20",
  },
  {
    model: "claude-fable-5-1[1m]",
    label: "Claude Fable 5.1",
    description: "👀 Anthropic: cached $0.25  · in $20    · out $50",
  },
  {
    model: "glm-5p3[1m]",
    label: "GLM 5.3",
    description: "🙈 Fireworks: cached $0.26  · in  $1.40 · out  $4.40",
  },
  {
    model: "kimi-k3[1m]",
    label: "Kimi K3",
    description: "👀 Fireworks: cached $0.30  · in  $3    · out $15",
  },
  {
    model: "ember-1[1m]",
    label: "[EXP] Ember (FW fine-tuned K3)",
    description: "👀 Fireworks: cached $0.30  · in  $3    · out $15",
  },
  {
    model: "qwen3p8-max",
    label: "[EXP] Qwen 3.8 Max",
    description: "👀 Fireworks: cached $0.25  · in  $2    · out  $6",
  },
  // Deprecated models live at the end of the list so they stay out of the way.
  {
    model: "deepseek-v4-flash-vision-exp[1m]",
    label: "[DEPR] DeepSeek V4 Flash Vision",
    description: "👀 Fireworks: cached $0.007 · in  $0.22 · out  $0.66",
  },
  {
    model: "deepseek-v4-pro-0813[1m]",
    label: "[DEPR] DeepSeek V4 Pro (0813)",
    description: "🙈 Fireworks: cached $0.044 · in  $1.32 · out  $3.96",
  },
  {
    model: "kimi-k2p6",
    label: "[DEPR] Kimi K2.6",
    description: "👀 Fireworks: cached $0.16  · in  $0.95 · out  $4",
  },
  {
    model: "glm-5p2[1m]",
    label: "[DEPR] GLM 5.2",
    description: "🙈 Fireworks: cached $0.14  · in  $1.40 · out  $4.40",
  },
  {
    model: "deepseek-v4-flash-0731[1m]",
    label: "[DEPR] DeepSeek V4 Flash (0731)",
    description: "🙈 Fireworks: cached $0.007 · in  $0.22 · out  $0.66",
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
settings.model = "glm-5p3-flash[1m]";
settings.effortLevel = "medium";
settings.env = {
  ...settings.env,
  // For now, Opus and Fable slots use the default claude models.
  // ANTHROPIC_DEFAULT_FABLE_MODEL: "kimi-k3[1m]",
  // ANTHROPIC_DEFAULT_OPUS_MODEL: "glm-5p3-flash[1m]",
  ANTHROPIC_DEFAULT_SONNET_MODEL: "deepseek-v4p1-flash[1m]",
  ANTHROPIC_DEFAULT_HAIKU_MODEL: "glm-5p3-flash[1m]",
  CLAUDE_CODE_SUBAGENT_MODEL: "glm-5p3-flash[1m]",
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

echo "*** Installing update-fireclaude self-updater..."
install_updater
echo

echo "*** All done, You can now use claude with fireworks models! Tips:"
echo "  - run 'fireconnect claude usage' to see detailed usage info for all sessions in the current directory"
echo "  - run 'fireconnect key export' to get your fireworks API key"
echo "  - run 'fireconnect claude off' to restore your claude config to its pre-fireworks state"
echo "  - run update-fireclaude to apply the latest settings (it is safely idempotent)"
echo
echo "*** WARNING: opus and fable slots now default to using anthropic models."
echo "  - prefer to use the exact model ids you want with /model or use the selector"
echo "  - similarly, use model ids in custom commands or agents if you want open models"
echo "  - for technical reasons, sonnet is deepseek-v4p1-flash and haiku is glm-5p3-flash."
echo "    this is not due to their relative strength or price."
