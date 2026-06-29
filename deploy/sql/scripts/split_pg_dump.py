#!/usr/bin/env python3
"""
split_pg_dump.py — Split pg_dump --schema-only output into per-object SQL files.

Usage:
    python3 split_pg_dump.py <input.sql> [output_dir]

Default output_dir: ./objects/ relative to this script.

Output structure:
    objects/
        extensions/       *.sql
        types/            *.sql  (domains, composite types)
        functions/        *.sql
        tables/           *.sql
        sequences/        *.sql
        indexes/          *.sql
        triggers/         *.sql
        constraints/      *.sql
        policies/         *.sql (RLS policies)
        views/            *.sql
        matviews/         *.sql
        defaults/         *.sql (sequence owned by, alter default)
        fkeys/            *.sql (foreign key constraints)
        misc/             *.sql (everything else)
"""

import os
import re
import sys

# ── pg_dump comment line patterns ──────────────────────────────────────────
RE_OBJECT_HEADER = re.compile(
    r'^--\s*Name:\s*(?P<name>.+?)\s*;\s*Type:\s*(?P<type>\S+(?:\s+\S+)?)\s*;\s*Schema:\s*(?P<schema>\S+)\s*;\s*Owner:\s*\S+'
)
RE_DUMP_HEADER_START = re.compile(r'^-- PostgreSQL database dump$')
RE_DUMP_HEADER_END   = re.compile(r'^SET row_security = off;$')
RE_DUMP_FOOTER       = re.compile(r'^-- PostgreSQL database dump complete$')

# Map pg_dump type → subdirectory name
TYPE_DIR = {
    'EXTENSION':              'extensions',
    'DOMAIN':                 'types',
    'TYPE':                   'types',
    'FUNCTION':               'functions',
    'TABLE':                  'tables',
    'TABLE & DATA':           'tables',
    'VIEW':                   'views',
    'MATERIALIZED VIEW':      'matviews',  # spell check ok
    'SEQUENCE':               'sequences',
    'SEQUENCE OWNED BY':      'defaults',
    'INDEX':                  'indexes',
    'INDEX ATTACH':           'indexes',
    'TRIGGER':                'triggers',
    'CONSTRAINT':             'constraints',
    'FK CONSTRAINT':          'fkeys',
    'CHECK CONSTRAINT':       'constraints',
    'DEFAULT':                'defaults',
    'POLICY':                 'policies',
    'ROW SECURITY':           'policies',
    'RULE':                   'misc',
    'AGGREGATE':              'misc',
    'OPERATOR':               'misc',
    'STATISTICS':             'misc',
    'PUBLICATION':            'misc',
    'SUBSCRIPTION':           'misc',
    'FOREIGN TABLE':          'tables',
    'FOREIGN DATA WRAPPER':   'misc',
    'SERVER':                 'misc',
    'TEXT SEARCH CONFIGURATION': 'misc',
    'TEXT SEARCH DICTIONARY': 'misc',
    'TEXT SEARCH PARSER':     'misc',
    'TEXT SEARCH TEMPLATE':   'misc',
}


def safe_filename(name: str) -> str:
    """Turn a pg_dump object name (may contain args like f(a,b)) into a file name."""
    # Strip function arguments for the file name, keep the base
    base = name.split('(')[0] if '(' in name else name
    # Replace characters unsafe for filenames
    safe = re.sub(r'[^\w.-]', '_', base)
    safe = re.sub(r'_+', '_', safe).strip('_')
    return safe.lower() if safe else 'unnamed'


def comment_block(name: str, obj_type: str, schema: str) -> str:
    """Return the header comment lines."""
    lines = []
    lines.append('-- =' + '=' * 74)
    lines.append(f"-- Object:   {name}")
    lines.append(f"-- Type:     {obj_type}")
    lines.append(f"-- Schema:   {schema}")
    lines.append('-- Source:   184_full_schema.sql (pg_dump --schema-only)')
    lines.append('-- =' + '=' * 74)
    lines.append('')
    return '\n'.join(lines)


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)
    input_path = sys.argv[1]
    script_dir = os.path.dirname(os.path.abspath(__file__))
    output_root = os.path.normpath(sys.argv[2]) if len(sys.argv) > 2 else os.path.join(script_dir, '..', 'objects')
    os.makedirs(output_root, exist_ok=True)

    # Ensure subdirectories exist
    for d in set(TYPE_DIR.values()):
        os.makedirs(os.path.join(output_root, d), exist_ok=True)

    with open(input_path, 'r') as f:
        lines = f.readlines()

    # ── Phase 1: Find object boundaries ────────────────────────────────
    # We scan for lines matching the header pattern.  Each object section
    # starts at a header line and ends just before the next header (or EOF).
    # Skip everything before the first object (dump header/global SETs).

    header_indices = []  # list of (line_num, match) for each -- Name: …; Type: …
    in_objects = False
    for i, line in enumerate(lines):
        if not in_objects:
            if RE_HEADER_END := (RE_DUMP_HEADER_END.search(line) if not in_objects else None):
                in_objects = True
            continue
        m = RE_OBJECT_HEADER.search(line)
        if m:
            header_indices.append((i, m))

    if not header_indices:
        print("ERROR: no object headers found in pg_dump output.")
        print("Make sure the file is a pg_dump --schema-only output.")
        sys.exit(1)

    # ── Phase 2: Extract and write each object section ─────────────────
    written = 0
    skipped = 0
    for idx, (start_ln, match) in enumerate(header_indices):
        end_ln = header_indices[idx + 1][0] if idx + 1 < len(header_indices) else len(lines)

        name = match.group('name')
        obj_type = match.group('type').strip()
        schema = match.group('schema').strip()
        subdir = TYPE_DIR.get(obj_type, 'misc')
        out_dir = os.path.join(output_root, subdir)
        os.makedirs(out_dir, exist_ok=True)

        # Build the file content: header comment + body lines
        body_lines = lines[start_ln:end_ln]
        # Strip trailing whitespace from each line, preserve the last newline
        body_text = ''.join(body_lines).rstrip('\n') + '\n'

        # Skip very small blocks that are just the header comment
        if body_text.strip() == '':
            skipped += 1
            continue

        filename = f"{schema}.{safe_filename(name)}.{obj_type.lower().replace(' ', '_').replace('&', 'and')}.sql"
        # For TABLE, drop the redundant 'table' suffix
        if obj_type == 'TABLE':
            filename = f"{schema}.{safe_filename(name)}.sql"
        elif obj_type == 'TABLE & DATA':
            filename = f"{schema}.{safe_filename(name)}.table_data.sql"

        filepath = os.path.join(out_dir, filename)

        final_content = comment_block(name, obj_type, schema) + body_text

        with open(filepath, 'w') as out:
            out.write(final_content)

        written += 1

    # ── Summary ─────────────────────────────────────────────────────────
    counts = {}
    for d in sorted(set(TYPE_DIR.values())):
        path = os.path.join(output_root, d)
        if os.path.isdir(path):
            n = len([x for x in os.listdir(path) if x.endswith('.sql')])
            if n > 0:
                counts[d] = n
    print(f"\nSplit complete: {written} objects written, {skipped} skipped.")
    print("Per-directory counts:")
    for d, n in sorted(counts.items(), key=lambda x: -x[1]):
        print(f"  {d}/: {n} files")
    print(f"\nOutput root: {output_root}")


if __name__ == '__main__':
    main()
