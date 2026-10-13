// Minimal RFC 4180 CSV reader for the eval dataset.
//
// The dataset holds prose prompts and rationales, so fields routinely contain
// commas and apostrophes. Quoted fields, doubled quotes, and quoted newlines
// are the only CSV features the reader has to support.

/**
 * Split CSV text into an array of row arrays.
 * @param {string} text
 * @returns {string[][]}
 */
export function parseCsvRows(text) {
  const rows = [];
  let row = [];
  let field = "";
  let inQuotes = false;
  const source = text.replace(/\r\n/g, "\n");
  let i = 0;

  while (i < source.length) {
    const c = source[i];

    if (inQuotes) {
      if (c === '"') {
        if (source[i + 1] === '"') {
          field += '"';
          i += 2;
          continue;
        }
        inQuotes = false;
        i += 1;
        continue;
      }
      field += c;
      i += 1;
      continue;
    }

    if (c === '"') {
      inQuotes = true;
      i += 1;
      continue;
    }
    if (c === ",") {
      row.push(field);
      field = "";
      i += 1;
      continue;
    }
    if (c === "\n") {
      row.push(field);
      rows.push(row);
      row = [];
      field = "";
      i += 1;
      continue;
    }
    field += c;
    i += 1;
  }

  if (field.length > 0 || row.length > 0) {
    row.push(field);
    rows.push(row);
  }

  return rows;
}

/**
 * Read a dataset with a header row into objects. Blank lines and lines whose
 * first field starts with `#` are ignored, so the file can carry comments.
 * @param {string} text
 * @returns {Record<string, string>[]}
 */
export function parseDataset(text) {
  const rows = parseCsvRows(text).filter((row) => {
    if (row.length === 1 && row[0].trim() === "") return false;
    return !row[0].trim().startsWith("#");
  });
  if (rows.length === 0) return [];

  const header = rows[0].map((h) => h.trim());
  const records = [];

  for (const row of rows.slice(1)) {
    const record = {};
    for (let i = 0; i < header.length; i += 1) {
      record[header[i]] = row[i] === undefined ? "" : row[i];
    }
    records.push(record);
  }

  return records;
}

/**
 * Validate the dataset shape. Returns a list of human-readable problems, so a
 * typo in the CSV is reported before any model call is spent.
 * @param {Record<string, string>[]} records
 * @returns {string[]}
 */
export function validateDataset(records) {
  const problems = [];
  const required = ["id", "class", "skill", "should_trigger", "prompt", "rationale"];
  const classes = new Set(["entry", "boundary", "internal-negative", "internal-positive"]);
  const seen = new Set();

  if (records.length === 0) problems.push("dataset is empty");

  records.forEach((record, index) => {
    const where = `row ${index + 2}`;
    for (const key of required) {
      if (!record[key] || record[key].trim() === "") {
        problems.push(`${where}: missing ${key}`);
      }
    }
    if (record.id) {
      if (seen.has(record.id)) problems.push(`${where}: duplicate id ${record.id}`);
      seen.add(record.id);
    }
    if (record.class && !classes.has(record.class)) {
      problems.push(`${where}: unknown class ${record.class}`);
    }
    if (record.should_trigger !== "true" && record.should_trigger !== "false") {
      problems.push(`${where}: should_trigger must be true or false, got ${record.should_trigger}`);
    }
  });

  return problems;
}
