// Run with: node --test test/setup-fireconnect.test.mjs
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

const scriptPath = fileURLToPath(new URL("../setup-fireconnect.sh", import.meta.url));
const fireworksModels = [
  "deepseek-v4p1-flash-1017[1m]",
  "glm-5p3-flash[1m]",
  "glm-5p3[1m]",
  "kimi-k3[1m]",
  "minimax-m3p1-flash[1m]",
  "ember-1[1m]",
  "qwen3p8-max",
];

function fixture(t) {
  const home = fs.mkdtempSync(path.join(os.tmpdir(), "afterburner-test-"));
  t.after(() => fs.rmSync(home, { recursive: true, force: true }));
  const bin = path.join(home, "bin");
  fs.mkdirSync(bin);
  for (const command of ["claude", "nexus"]) {
    fs.writeFileSync(path.join(bin, command), "#!/bin/sh\nexit 0\n", { mode: 0o700 });
  }
  // Use only fake CLIs and a known Node binary; never upgrade or authenticate
  // real tools, even if a future change attempts to download an installer.
  for (const command of ["curl", "wget"]) {
    fs.writeFileSync(path.join(bin, command), "#!/bin/sh\nexit 99\n", { mode: 0o700 });
  }
  fs.symlinkSync(process.execPath, path.join(bin, "node"));

  const settingsPath = path.join(home, ".claude", "settings.json");
  const configPath = path.join(home, ".claude.json");
  return {
    home,
    settingsPath,
    configPath,
    writeSettings(settings) {
      fs.mkdirSync(path.dirname(settingsPath), { recursive: true });
      fs.writeFileSync(settingsPath, JSON.stringify(settings));
    },
    run() {
      return spawnSync("/bin/bash", [scriptPath], {
        cwd: home,
        env: { HOME: home, PATH: `${bin}:/usr/bin:/bin` },
        encoding: "utf8",
        timeout: 10000,
      });
    },
  };
}

function assertPicker(settings) {
  assert.equal(settings.modelPicker.replaceBuiltInOptions, false);
  assert.deepEqual(settings.modelPicker.options.map(({ model }) => model), fireworksModels);
  assert.equal(settings.model, "glm-5p3-flash[1m]");
}

function assertSuccess(result) {
  assert.equal(result.error, undefined);
  assert.equal(result.status, 0, result.stderr);
}

test("fresh setup appends only Fireworks options to the built-in picker", (t) => {
  const f = fixture(t);
  assertSuccess(f.run());
  assertPicker(JSON.parse(fs.readFileSync(f.settingsPath, "utf8")));
  assert.ok(fs.existsSync(path.join(f.home, ".local", "bin", "update-fireclaude")));
});

test("existing setup restores built-in options and removes stale Anthropic rows", (t) => {
  const f = fixture(t);
  const permissions = { deny: ["Bash(rm:*)"] };
  const env = { ANTHROPIC_BASE_URL: "https://example.invalid/inference" };
  f.writeSettings({
    permissions,
    env,
    theme: "light",
    modelPicker: {
      replaceBuiltInOptions: true,
      options: [{ model: "claude-fable-5-1[1m]", label: "Claude Fable 5.1" }],
    },
  });
  fs.writeFileSync(f.configPath, JSON.stringify({
    orgModelDefaultCache: { model: "claude-fable-5-1" },
    unrelated: "preserved",
  }));

  assertSuccess(f.run());
  const settings = JSON.parse(fs.readFileSync(f.settingsPath, "utf8"));
  assertPicker(settings);
  assert.deepEqual(settings.permissions, permissions);
  assert.deepEqual(settings.env, env);
  assert.equal(settings.theme, "light");
  assert.deepEqual(JSON.parse(fs.readFileSync(f.configPath, "utf8")), { unrelated: "preserved" });
});

test("rerunning setup is idempotent and keeps built-in options enabled", (t) => {
  const f = fixture(t);
  assertSuccess(f.run());
  const first = fs.readFileSync(f.settingsPath, "utf8");
  assertSuccess(f.run());
  assert.equal(fs.readFileSync(f.settingsPath, "utf8"), first);
  assertPicker(JSON.parse(first));
});

test("invalid existing settings fail without overwriting the file", (t) => {
  const f = fixture(t);
  f.writeSettings({});
  const invalid = "{invalid json";
  fs.writeFileSync(f.settingsPath, invalid);
  const result = f.run();
  assert.equal(result.error, undefined);
  assert.notEqual(result.status, 0);
  assert.equal(fs.readFileSync(f.settingsPath, "utf8"), invalid);
});
