#!/usr/bin/env bash
#
# Print a markdown inventory of the UI's hard-coded typography, colour and
# radius values. Phase 1 uses this as the before/after measurement for the
# design-token migration; Phase 5 uses it as a "no new literals" check.
#
# Usage:
#   Scripts/ui_token_inventory.sh
#   Scripts/ui_token_inventory.sh > .ui-baseline/token-inventory.md

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

count() {
    grep -rhoF "$1" revert --include='*.swift' 2>/dev/null | wc -l | tr -d ' '
}

count_regex() {
    grep -rhoE "$1" revert --include='*.swift' 2>/dev/null | wc -l | tr -d ' '
}

font_sizes="$(
    grep -rhoE '\.font\(\.scaledSystem\(size: [0-9][0-9.]*' revert --include='*.swift' 2>/dev/null \
        | sed 's/.*size: //' \
        | sort -n \
        | uniq \
        | tr '\n' ' '
)"

commit="$(git rev-parse --short HEAD 2>/dev/null || echo 'unknown')"
dirty="$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')"

cat <<EOF
# UI token inventory

- Generated: $(date +%Y-%m-%dT%H:%M:%S%z)
- Commit: \`$commit\` ($dirty working-tree changes)
- Scope: \`revert/**/*.swift\` (app target only)

## Typography

| Metric | Count |
|---|---:|
| \`.font(.system(size:))\` fixed call sites | $(count '.font(.system(size:') |
| \`.font(.scaledSystem(size:))\` Dynamic Type call sites | $(count '.font(.scaledSystem(size:') |
| Semantic \`.font(.system(.style, ...))\` | $(count '.font(.system(.') |
| \`scaledSystem\` helper references | $(count 'scaledSystem') |
| \`dynamicTypeSize\` overrides | $(count 'dynamicTypeSize') |
| Distinct base sizes | $(printf '%s' "$font_sizes" | wc -w | tr -d ' ') |

Distinct base sizes: \`$font_sizes\`

## Components and tokens

| Metric | Count |
|---|---:|
| \`PulseScreenHeader(\` compatibility usages | $(count 'PulseScreenHeader(') |
| \`RevertScreenHeader(\` compatibility usages | $(count 'RevertScreenHeader(') |
| \`ScreenHeader(\` layout call sites | $(count 'ScreenHeader(') |
| \`cornerRadius\` references | $(count 'cornerRadius') |
| Hex colour literals | $(count_regex '0x[0-9A-Fa-f]{6,8}') |
| \`Color(red:\` literals | $(count 'Color(red:') |
| \`String(format:\` calls | $(count 'String(format:') |
| \`accessibilityIdentifier\` references | $(count 'accessibilityIdentifier') |

## Phase 1 invariants

- No view uses a fixed \`.font(.system(size:))\`; all 472 call sites go through
  \`.scaledSystem(size:)\`, which infers a text style and scales with
  \`UIFontMetrics\`.
- \`ScreenHeader\` is the only header layout. \`PulseScreenHeader\` and
  \`RevertScreenHeader\` are compatibility wrappers that preserve the existing
  visual treatment.
- Riders' distances, speeds, elevations and calendar dates go through
  \`RevertFormat\`. Remaining \`String(format:)\` calls are machine/log strings
  and the fixed \`h:mm:ss\` clock.
- Primary hit targets are 44pt: circle buttons, segmented controls and tab
  items.
EOF
