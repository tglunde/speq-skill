// Scoring one dataset row against its captured runs.
//
// A trigger decision is stochastic, so a row is scored over N runs and the
// majority decides. Unanimity is tracked separately: a row that passes 2 of 3
// is a weaker signal than one that passes 3 of 3, and the difference is the
// first thing to look at when a score moves.

/**
 * @typedef {object} RunOutcome
 * @property {"ok"|"error"} status
 * @property {string[]} loaded   Skill names loaded in the run.
 * @property {string[]} advertised
 * @property {object} stats
 * @property {string} [error]    Failure detail when status is "error".
 * @property {string} [tracePath]
 */

/**
 * Score a single run: did the named skill's presence match the expectation?
 * @param {{skill: string, should_trigger: string}} row
 * @param {RunOutcome} run
 * @returns {boolean}
 */
export function scoreRun(row, run) {
  const loaded = run.loaded.includes(row.skill);
  return loaded === (row.should_trigger === "true");
}

/**
 * Score one row over its runs.
 * @param {object} row
 * @param {RunOutcome[]} runs
 * @returns {object}
 */
export function gradeRow(row, runs) {
  const expected = row.should_trigger === "true";
  const usable = runs.filter((run) => run.status === "ok");

  const base = {
    id: row.id,
    class: row.class,
    skill: row.skill,
    expected,
    prompt: row.prompt,
    rationale: row.rationale,
    runs: runs.length,
    usableRuns: usable.length,
    errors: runs.length - usable.length,
    loadedUnion: [...new Set(usable.flatMap((run) => run.loaded))].sort(),
  };

  if (usable.length === 0) {
    return {
      ...base,
      verdict: "ERROR",
      passes: 0,
      unanimous: false,
      noise: [],
      detail: runs.find((run) => run.error)?.error ?? "no usable runs",
    };
  }

  const passes = usable.filter((run) => scoreRun(row, run)).length;
  const verdict = passes * 2 > usable.length ? "PASS" : "FAIL";
  const unanimous = passes === usable.length || passes === 0;

  // Skills loaded that the row did not ask about. A run that loads the right
  // skill plus four others is not the same result as a run that loads only the
  // right one.
  const noise = [...new Set(usable.flatMap((run) => run.loaded.filter((s) => s !== row.skill)))].sort();

  return {
    ...base,
    verdict,
    passes,
    unanimous,
    noise,
    flaky: !unanimous,
  };
}

/**
 * Aggregate graded rows into a report.
 * @param {object[]} graded
 * @param {object} meta
 */
export function buildReport(graded, meta) {
  const scored = graded.filter((row) => row.verdict !== "ERROR");
  const byClass = {};

  for (const row of graded) {
    const bucket = (byClass[row.class] ??= { total: 0, pass: 0, fail: 0, error: 0, flaky: 0 });
    bucket.total += 1;
    if (row.verdict === "PASS") bucket.pass += 1;
    else if (row.verdict === "FAIL") bucket.fail += 1;
    else bucket.error += 1;
    if (row.flaky) bucket.flaky += 1;
  }

  const totals = {
    rows: graded.length,
    scored: scored.length,
    pass: scored.filter((row) => row.verdict === "PASS").length,
    fail: scored.filter((row) => row.verdict === "FAIL").length,
    error: graded.length - scored.length,
    flaky: scored.filter((row) => row.flaky).length,
  };

  return {
    meta,
    totals,
    passRate: totals.scored === 0 ? 0 : totals.pass / totals.scored,
    byClass,
    rows: graded,
  };
}

/**
 * Render the report as Markdown, conclusion first.
 * @param {object} report
 * @returns {string}
 */
export function renderMarkdown(report) {
  const { meta, totals, byClass } = report;
  const pct = (value, total) => (total === 0 ? "n/a" : `${Math.round((value / total) * 100)}%`);
  const lines = [];

  lines.push("# Trigger Eval Report");
  lines.push("");
  lines.push(
    `**${totals.pass} of ${totals.scored} rows pass (${pct(totals.pass, totals.scored)}).** ` +
      `${totals.fail} fail, ${totals.flaky} are not unanimous, ${totals.error} could not run.`,
  );
  lines.push("");
  lines.push("## Run");
  lines.push("");
  lines.push(`- Model: \`${meta.model}\``);
  lines.push(`- Skill set: \`${meta.skillSet}\` (${meta.skillCount} skills, ${meta.tree})`);
  lines.push(`- Runs per row: ${meta.runs}`);
  lines.push(`- Dataset: ${meta.dataset} (${meta.datasetRows} rows)`);
  lines.push(`- Started: ${meta.startedAt}`);
  if (meta.skillTreeHash) lines.push(`- Skill tree hash: \`${meta.skillTreeHash}\``);
  if (meta.commit) lines.push(`- Commit: \`${meta.commit}\`${meta.dirty ? " (dirty tree)" : ""}`);
  if (meta.piVersion) lines.push(`- Pi version: ${meta.piVersion}`);
  lines.push("");

  lines.push("## By class");
  lines.push("");
  lines.push("| Class | Rows | Pass | Fail | Flaky | Error | Pass rate |");
  lines.push("|---|---|---|---|---|---|---|");
  for (const [name, bucket] of Object.entries(byClass)) {
    lines.push(
      `| ${name} | ${bucket.total} | ${bucket.pass} | ${bucket.fail} | ${bucket.flaky} | ${bucket.error} | ${pct(bucket.pass, bucket.total - bucket.error)} |`,
    );
  }
  lines.push("");

  const failures = report.rows.filter((row) => row.verdict === "FAIL");
  lines.push("## Failures");
  lines.push("");
  if (failures.length === 0) {
    lines.push("None.");
  } else {
    for (const row of failures) {
      lines.push(`### ${row.id}: ${row.skill} should${row.expected ? "" : " not"} trigger`);
      lines.push("");
      lines.push(`> ${row.prompt}`);
      lines.push("");
      lines.push(`- Passed ${row.passes} of ${row.usableRuns} runs`);
      lines.push(`- Loaded: ${row.loadedUnion.length === 0 ? "(nothing)" : row.loadedUnion.join(", ")}`);
      lines.push(`- Why this expectation: ${row.rationale}`);
      lines.push("");
    }
  }

  const flaky = report.rows.filter((row) => row.flaky);
  lines.push("## Not unanimous");
  lines.push("");
  if (flaky.length === 0) {
    lines.push("None.");
  } else {
    lines.push("| Row | Skill | Expected | Passes | Loaded |");
    lines.push("|---|---|---|---|---|");
    for (const row of flaky) {
      lines.push(
        `| ${row.id} | ${row.skill} | ${row.expected ? "trigger" : "no trigger"} | ${row.passes}/${row.usableRuns} | ${row.loadedUnion.join(", ") || "(nothing)"} |`,
      );
    }
  }
  lines.push("");

  lines.push("## All rows");
  lines.push("");
  lines.push("| Row | Class | Skill | Expected | Verdict | Passes | Also loaded |");
  lines.push("|---|---|---|---|---|---|---|");
  for (const row of report.rows) {
    lines.push(
      `| ${row.id} | ${row.class} | ${row.skill} | ${row.expected ? "trigger" : "no trigger"} | ${row.verdict} | ${row.passes}/${row.usableRuns} | ${row.noise?.join(", ") || ""} |`,
    );
  }
  lines.push("");

  return lines.join("\n");
}
