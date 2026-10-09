#!/usr/bin/env bash
# Build the PDF manuals from their Typst sources. Requires Typst >= 0.15 (https://typst.app).
# Fonts are vendored in fonts/ so the output does not depend on the fonts installed on the machine.
set -euo pipefail
cd "$(dirname "$0")"
root="$(git rev-parse --show-toplevel)"
# Fixed creation date (the document date in lib/facts.typ) so an unchanged source gives a byte-identical PDF
date="$(sed -n 's/^#let doc-date = "\(.*\)"/\1/p' lib/facts.typ)"
export SOURCE_DATE_EPOCH="$(date -u -d "$date" +%s)"
for src in technical-design.en technical-design.vi operations-runbook.en operations-runbook.vi; do
  [ -f "$src.typ" ] || continue
  typst compile --root "$root" --font-path fonts --ignore-system-fonts "$src.typ" "$src.pdf"
  echo "built docs/manuals/$src.pdf"
done
