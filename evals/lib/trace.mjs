// Reading Pi JSON-mode traces and deciding which skills a run loaded.
//
// Pi has no skill-invocation event. It advertises each skill by name,
// description, and path in the system prompt, then loads the full instructions
// only when the model reads the file. So a skill counts as loaded when a tool
// call touches a file inside that skill's directory.
//
// Two traps shape the matcher:
//
//   1. The system prompt already contains every skill path. Scanning the whole
//      trace would report every advertised skill as loaded, so only tool-call
//      arguments are scanned.
//   2. `speq-plan` is a prefix of `speq-plan-pr`. The matcher therefore anchors
//      on the directory boundary (`skills/<name>/`) and requires a file below
//      it, so a bare `ls` of a skill directory is not a load either.
//
// A load is not the same as a choice. The orchestrator skills are required by
// their own text to read sibling skills (`speq-plan-pr` reads `/skill:speq-plan`
// references, `speq-code-review` reads `/skill:speq-code-guardrails`). Those
// reads are delegations from the entry point, so `entrySkill` reports the first
// skill a run reached for and the grader scores a "must not trigger" row on it.

/** Matches a file path inside a skill directory and captures the skill name. */
const SKILL_FILE = /skills\/(speq-[a-z0-9-]+)\/(?:[A-Za-z0-9_.-]+\/)*[A-Za-z0-9_.-]+\.[A-Za-z0-9]+/g;

/**
 * Parse a JSONL stream. Malformed lines are skipped rather than fatal, because
 * a killed run can end mid-record.
 * @param {string} text
 * @returns {object[]}
 */
export function parseJsonl(text) {
  const events = [];
  for (const rawLine of text.split("\n")) {
    const line = rawLine.endsWith("\r") ? rawLine.slice(0, -1) : rawLine;
    if (line.trim() === "") continue;
    try {
      events.push(JSON.parse(line));
    } catch {
      // Partial trailing record from an aborted run.
    }
  }
  return events;
}

function asArray(value) {
  return Array.isArray(value) ? value : [];
}

function safeStringify(value) {
  if (value === undefined || value === null) return "";
  if (typeof value === "string") return value;
  try {
    return JSON.stringify(value);
  } catch {
    return String(value);
  }
}

function collectToolCallArguments(message, into) {
  if (!message || message.role !== "assistant") return;
  for (const block of asArray(message.content)) {
    if (!block || typeof block !== "object") continue;
    if (block.type === "toolCall" || block.type === "tool_call") {
      into.push(block.arguments ?? block.args ?? block.input ?? block.parameters);
    }
  }
}

/**
 * Every argument payload of a tool call in the run, in stream order.
 * @param {object[]} events
 * @returns {unknown[]}
 */
export function collectToolArguments(events) {
  const args = [];
  for (const event of events) {
    if (event.type === "tool_execution_start" || event.type === "tool_execution_end") {
      if (event.args !== undefined) args.push(event.args);
    }
    if (event.type === "message_end" || event.type === "turn_end") {
      collectToolCallArguments(event.message, args);
    }
  }
  return args;
}

/**
 * Skill names whose instructions the run actually loaded, from tool-call
 * arguments only. The system prompt is deliberately not scanned.
 * @param {object[]} events
 * @returns {Set<string>}
 */
export function loadedSkills(events) {
  const found = new Set();
  for (const args of collectToolArguments(events)) {
    const text = safeStringify(args);
    if (text === "") continue;
    for (const match of text.matchAll(SKILL_FILE)) found.add(match[1]);
  }
  return found;
}

/**
 * The skill a run reached for first, from tool-call arguments in stream order.
 * This is the run's entry point: the skill whose instructions the model chose
 * to follow. Null when the run read no skill file at all.
 * @param {object[]} events
 * @returns {string|null}
 */
export function entrySkill(events) {
  for (const args of collectToolArguments(events)) {
    const text = safeStringify(args);
    if (text === "") continue;
    for (const match of text.matchAll(SKILL_FILE)) return match[1];
  }
  return null;
}

/**
 * Skill names the system prompt advertised. This is a diagnostic: it confirms
 * the eval loaded the intended tree, and it separates "the skill was never
 * offered" from "the model did not pick it".
 * @param {object[]} events
 * @returns {Set<string>}
 */
export function advertisedSkills(events) {
  const found = new Set();
  for (const event of events) {
    const message = event.message;
    if (!message) continue;
    const sections = message.sections;
    if (!sections || typeof sections !== "object") continue;
    for (const value of Object.values(sections)) {
      const text = safeStringify(value);
      for (const match of text.matchAll(/name:\s*(speq-[a-z0-9-]+)/g)) found.add(match[1]);
      for (const match of text.matchAll(/skills\/(speq-[a-z0-9-]+)\/SKILL\.md/g)) found.add(match[1]);
    }
  }
  return found;
}

/**
 * Tool-call count and token totals for the run, for the efficiency checks the
 * blog calls out. Missing usage fields stay zero.
 * @param {object[]} events
 */
export function runStats(events) {
  let toolCalls = 0;
  let inputTokens = 0;
  let outputTokens = 0;
  let totalTokens = 0;

  for (const event of events) {
    if (event.type === "tool_execution_start") toolCalls += 1;
    const usage = event.usage ?? event.message?.usage;
    if (usage && typeof usage === "object") {
      if (typeof usage.input === "number") inputTokens = Math.max(inputTokens, usage.input);
      if (typeof usage.output === "number") outputTokens = Math.max(outputTokens, usage.output);
      if (typeof usage.totalTokens === "number") totalTokens = Math.max(totalTokens, usage.totalTokens);
    }
  }

  return { toolCalls, inputTokens, outputTokens, totalTokens };
}

/**
 * Turn one captured run into the facts the grader needs.
 * @param {object[]} events
 * @returns {{loaded: string[], entry: string|null, advertised: string[], stats: object}}
 */
export function summarizeRun(events) {
  return {
    loaded: [...loadedSkills(events)].sort(),
    entry: entrySkill(events),
    advertised: [...advertisedSkills(events)].sort(),
    stats: runStats(events),
  };
}
