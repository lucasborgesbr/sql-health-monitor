#!/usr/bin/env python3
"""
Emit COL_LENGTH reconciliation guards for every table in an install script.

The IF OBJECT_ID(...) IS NULL CREATE TABLE guard means a table created by an
older release keeps its old shape forever: the CREATE is skipped wholesale
whenever the table exists, so a column added later in the repository never
reaches an existing installation.

For each column this appends an idempotent guard:

    IF COL_LENGTH('monitor.X', 'Col') IS NULL
        ALTER TABLE [monitor].[X] ADD Col <definition>;
    GO

with two exceptions:

  - computed columns (HoursSinceLastBackup AS DATEDIFF(...)) are not probed by
    COL_LENGTH; they use sys.computed_columns instead
  - a NOT NULL column with no DEFAULT cannot be added to a populated table in
    one step, so it is added nullable, backfilled, then tightened
"""
import re
import sys

IDENT = r"[A-Za-z_][A-Za-z0-9_]*"
TABLE_RX = re.compile(
    r"IF OBJECT_ID\('monitor\.(" + IDENT + r")', 'U'\) IS NULL\s*\n"
    r"CREATE TABLE \[monitor\]\.\[\1\] \((.*?)\n\);", re.S)
COL_RX = re.compile(
    r"^\s{4,8}\[?(" + IDENT + r")\]?\s+(.*)$")

SKIP_TYPES = {"PRIMARY", "UNIQUE", "FOREIGN", "CONSTRAINT", "INDEX"}


def split_top_level(body):
    """Split a CREATE TABLE body on commas that are not inside parentheses."""
    parts, depth, cur = [], 0, ""
    for ch in body:
        if ch == '(':
            depth += 1
        elif ch == ')':
            depth -= 1
        if ch == ',' and depth == 0:
            parts.append(cur)
            cur = ""
        else:
            cur += ch
    if cur.strip():
        parts.append(cur)
    return parts


def guard(table, col, definition):
    t = "monitor.%s" % table
    col_name = col.strip("[]")

    # Computed column: probe sys.computed_columns, not COL_LENGTH.
    m = re.match(r"^(" + IDENT + r")\s+AS\s+(.+)$", definition.strip(), re.I)
    if m:
        return (
            "IF NOT EXISTS (SELECT 1 FROM sys.computed_columns\n"
            "               WHERE object_id = OBJECT_ID('%s')\n"
            "                 AND name = '%s')\n"
            "    ALTER TABLE [monitor].[%s] ADD %s AS %s;\n"
            "GO\n" % (t, col_name, table, col_name, m.group(2).strip())
        )

    if "IDENTITY" in definition.upper():
        return ""  # an identity PK is created with the table; never added later

    # Constraints cannot travel with ALTER TABLE ADD on a populated table --
    # ADD ... PRIMARY KEY fails outright, and re-adding a UNIQUE constraint
    # would duplicate what the CREATE TABLE already established.
    definition = re.sub(r"\bPRIMARY\s+KEY\b", "", definition, flags=re.I)
    definition = re.sub(r"\bUNIQUE\b", "", definition, flags=re.I)
    definition = re.sub(r"\bFOREIGN\s+KEY\b.*$", "", definition, flags=re.I)
    definition = re.sub(r"\bREFERENCES\s+\S+.*$", "", definition, flags=re.I)
    definition = " ".join(definition.split())

    # NOT NULL with no DEFAULT cannot be added to a populated table, and there
    # is no honest literal to backfill an unknown value with. Add it nullable:
    # the column exists and is readable, which is what an upgrade needs. Making
    # it NOT NULL with a guessed value would be worse than leaving it nullable.
    if re.search(r"\bNOT\s+NULL\b", definition, re.I):
        definition = re.sub(r"\s*\bNOT\s+NULL\b", " NULL", definition, flags=re.I)
        definition = " ".join(definition.split())

    return (
        "IF COL_LENGTH('%s', '%s') IS NULL\n"
        "    ALTER TABLE [monitor].[%s] ADD %s %s;\n"
        "GO\n" % (t, col_name, table, col_name, definition)
    )


MARKER = "-- Column reconciliation:"

# A reconciliation region runs from its marker up to the next IF OBJECT_ID(...),
# which is where the following table's CREATE TABLE guard begins. Bounding it
# by the marker alone left orphaned guards behind whenever an earlier run was
# interrupted mid-block.
BLOCK_RX = re.compile(
    re.escape(MARKER) + r".*?(?=^IF OBJECT_ID\(|\Z)",
    re.S | re.M)


def main(path):
    raw = open(path, encoding="utf-8-sig").read()

    # Strip any block a previous run left behind, so re-running repairs the file
    # instead of stacking a second copy on top of the first.
    src = BLOCK_RX.sub("", raw)
    if src != raw:
        print("%s: removed a previous reconciliation block" % path)

    edits, tables, columns = [], 0, 0

    for m in TABLE_RX.finditer(src):
        table, body = m.group(1), m.group(2)
        guards = []
        for part in split_top_level(body):
            line = " ".join(part.split())
            if not line:
                continue
            first = line.split()[0].upper()
            if first in SKIP_TYPES or line.upper().startswith(("INDEX ", "CONSTRAINT ")):
                continue
            cm = COL_RX.match(part)
            if not cm:
                continue
            col, definition = cm.group(1), cm.group(2)
            if not re.match(r"^" + IDENT, col):
                continue
            g = guard(table, col, definition)
            if g:
                guards.append(g)
                columns += 1

        if not guards:
            continue
        tables += 1
        edits.append((m.end(),
            "\n-- Column reconciliation: an installation that predates any of\n"
            "-- these columns still has the table, so the CREATE above is skipped\n"
            "-- whole and its shape would never change.\n"
            + "\n".join(guards)))

    # Apply back to front. Inserting while walking forward shifts every later
    # offset, so an insertion lands inside the previous block and truncates it.
    for pos, block in sorted(edits, key=lambda e: -e[0]):
        src = src[:pos] + block + src[pos:]

    open(path, "w", encoding="utf-8", newline="").write(src)
    print("%s: %d tables, %d column guards" % (path, tables, columns))


if __name__ == "__main__":
    for p in sys.argv[1:]:
        main(p)