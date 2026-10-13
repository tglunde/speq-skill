#!/usr/bin/env node
// Stand-in for `pi` in the runner's integration test.
//
// It emits a well-formed Pi JSON-mode stream so the runner's workspace
// preparation, process handling, trace parsing, scoring, and reporting can be
// exercised without a model or credentials.
//
// STUB_PI_SKILLS is a comma-separated list of skills the stub reports as
// loaded. Everything else is advertised but never read.

import { readFileSync, writeFileSync } from "node:fs";

const argv = process.argv.slice(2);

if (argv.includes("--version") && process.env.STUB_PI_IGNORE_VERSION !== "1") {
  process.stdout.write("0.0.0-stub\n");
  process.exit(0);
}

const prompt = argv.at(-1) ?? "";

const skillDirs = [];
for (let i = 0; i < argv.length - 1; i += 1) {
  if (argv[i] === "--skill") skillDirs.push(argv[i + 1]);
}

const advertised = skillDirs
  .map((dir) => {
    const name = dir.replace(/\/+$/, "").split("/").at(-1);
    return { name, path: `${dir}/SKILL.md` };
  })
  .sort((a, b) => a.name.localeCompare(b.name));

// STUB_PI_SKILLS is what the stub reports as loaded. When STUB_PI_STATE names
// a counter file and STUB_PI_LOAD_ON lists run numbers, the stub loads only on
// those runs, which lets the runner's tests produce a deterministic split vote.
function shouldLoadThisRun() {
  const statePath = process.env.STUB_PI_STATE;
  if (!statePath) return true;

  let count = 0;
  try {
    count = Number(readFileSync(statePath, "utf8")) || 0;
  } catch {
    count = 0;
  }
  count += 1;
  writeFileSync(statePath, String(count));

  const loadOn = (process.env.STUB_PI_LOAD_ON ?? "")
    .split(",")
    .map((value) => value.trim())
    .filter(Boolean);
  return loadOn.includes(String(count));
}

const loaded = shouldLoadThisRun()
  ? (process.env.STUB_PI_SKILLS ?? "")
      .split(",")
      .map((name) => name.trim())
      .filter(Boolean)
  : [];

function emit(record) {
  process.stdout.write(`${JSON.stringify(record)}\n`);
}

const skillSection = advertised
  .map((skill) => `<skill>\nname: ${skill.name}\ndescription: stub\ndescription for ${skill.name}\npath: ${skill.path}\n</skill>`)
  .join("\n");

emit({ type: "session", version: 3, id: "stub-session", timestamp: new Date().toISOString(), cwd: process.cwd() });
emit({ type: "agent_start" });
emit({
  type: "message_end",
  message: {
    role: "system",
    content: "",
    sections: { skills: `<skills>\n${skillSection}\n</skills>` },
    timestamp: Date.now(),
  },
});
emit({ type: "turn_start" });

loaded.forEach((name, index) => {
  const dir = skillDirs.find((candidate) => candidate.replace(/\/+$/, "").endsWith(`/${name}`)) ?? `stub/${name}`;
  const path = `${dir}/SKILL.md`;
  const args = { path };
  emit({ type: "tool_execution_start", toolCallId: `stub-${index}`, toolName: "read", args });
  emit({ type: "tool_execution_end", toolCallId: `stub-${index}`, toolName: "read", args, isError: false, durationMs: 1 });
});

emit({
  type: "message_end",
  message: {
    role: "assistant",
    content: [{ type: "text", text: `stub answer for: ${prompt}` }],
    usage: { input: 100, output: 10, totalTokens: 110 },
  },
});
emit({ type: "turn_end", message: { role: "assistant", content: [] }, toolResults: [] });
emit({ type: "agent_end", messages: [], willRetry: false });
emit({ type: "agent_settled", aborted: false });
