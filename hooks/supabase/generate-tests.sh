#!/usr/bin/env bash
# Stop hook: scaffold missing test files for data-access operations.
#
# TODO: adjust OPS_ROOT and the import path in the skeleton to match your
# project's data-access directory and vitest setup.
set -euo pipefail

payload=$(cat)

active=$(echo "$payload" | jq -r '.stop_hook_active // false')
if [[ "$active" == "true" ]]; then
  exit 0
fi

command -v python3 >/dev/null 2>&1 || exit 0

# TODO: change this path if your data-access layer lives elsewhere.
OPS_ROOT_PATH="${OPS_ROOT_PATH:-packages/database/operations/src}"

[[ -d "$OPS_ROOT_PATH" ]] || exit 0

OPS_ROOT_PATH="$OPS_ROOT_PATH" python3 - <<'PY' || true
import os, re, csv, datetime, pathlib, sys

OPS_ROOT = pathlib.Path(os.environ.get("OPS_ROOT_PATH", "packages/database/operations/src"))
REGISTRY = pathlib.Path("docs/tests/test-registry.csv")
REGISTRY_HEADER = [
    "id", "domain", "feature", "scenario", "actor_type",
    "preconditions", "expected_output", "business_rule_ref",
    "test_runner", "priority", "status", "last_run", "last_result",
]
SKIP_NAMES = {"index.ts", "vitest.setup.ts"}

# TODO: customize these keyword → domain rules for your project.
DOMAIN_RULES = [
    (("auth", "signin", "signup", "session"), "auth"),
    (("user", "profile", "account"),          "users"),
    (("billing", "subscription", "invoice"),  "billing"),
]

def classify_domain(path_str: str) -> str:
    low = path_str.lower()
    for keywords, name in DOMAIN_RULES:
        if any(k in low for k in keywords):
            return name
    return "general"

def to_camel_case(basename_no_ext: str) -> str:
    parts = re.split(r"[-_]", basename_no_ext)
    if not parts:
        return basename_no_ext
    return parts[0] + "".join(p[:1].upper() + p[1:] for p in parts[1:])

def relative_import(from_test: pathlib.Path, to_target: pathlib.Path) -> str:
    rel = os.path.relpath(to_target.with_suffix(""), start=from_test.parent)
    rel = rel.replace(os.sep, "/")
    if not rel.startswith("."):
        rel = "./" + rel
    return rel

def skeleton(op_name: str, import_op: str, import_setup: str) -> str:
    return f"""import {{ describe, it, expect }} from 'vitest';
import {{
  anonClient,
  consumerClient,
  businessClient,
  staffClient,
}} from '{import_setup}';
import {{ {op_name} }} from '{import_op}';

// TODO: test registry entry — see docs/tests/test-registry.csv
// Every data-access operation must cover the actor types your project uses.

describe('{op_name}', () => {{
  it('happy path — returns expected entity', async () => {{
    expect.fail('not implemented');
  }});

  it('rejects invalid input with a typed OperationError', async () => {{
    expect.fail('not implemented');
  }});

  describe('RLS enforcement', () => {{
    it('anon: denied', async () => {{
      void anonClient;
      expect.fail('not implemented');
    }});

    it('consumer: scoped to own user', async () => {{
      void consumerClient;
      expect.fail('not implemented');
    }});

    it('business user: scoped to own tenant', async () => {{
      void businessClient;
      expect.fail('not implemented');
    }});

    it('staff: allowed with cross-tenant privilege', async () => {{
      void staffClient;
      expect.fail('not implemented');
    }});
  }});
}});
"""

def should_skip(path: pathlib.Path) -> bool:
    name = path.name
    if name in SKIP_NAMES:
        return True
    if name.endswith(".d.ts") or name.endswith(".test.ts") or name.endswith(".spec.ts"):
        return True
    if "__tests__" in path.parts:
        return True
    # Shared-internal convention: _*.ts files are infrastructure, not units of behavior.
    if name.startswith("_"):
        return True
    return False

def has_consolidated_test(src: pathlib.Path) -> bool:
    # A consolidated test file <dir-basename>.test.ts in __tests__/ covers
    # every op in the directory; per-op stubs would be redundant noise.
    consolidated = src.parent / "__tests__" / (src.parent.name + ".test.ts")
    return consolidated.exists()

EXPORT_CONST_RE = re.compile(r"export\s+(?:const|function|class|async\s+function)\s+(\w+)")
EXPORT_LIST_RE = re.compile(r"export\s*\{([^}]*)\}")
SUFFIX_STRIPS = ("WithServiceRole", "WithUserClient", "WithAdminClient")

def resolve_exports(src: pathlib.Path) -> list:
    try:
        text = src.read_text()
    except Exception:
        return []
    names = list(EXPORT_CONST_RE.findall(text))
    for match in EXPORT_LIST_RE.findall(text):
        for part in match.split(","):
            token = part.strip().split(" as ")[0].strip()
            if token:
                names.append(token)
    return names

def matches_basename(exports: list, basename: str) -> str:
    camel = to_camel_case(basename)
    candidates = {camel}
    for suffix in SUFFIX_STRIPS:
        if camel.endswith(suffix):
            candidates.add(camel[: -len(suffix)])
    # Also consider exports whose name, with suffix stripped, matches the basename camel.
    for name in exports:
        if name in candidates:
            return name
        for suffix in SUFFIX_STRIPS:
            if name.endswith(suffix) and name[: -len(suffix)] == camel:
                return name
    return ""

def auto_id(basename: str) -> str:
    return "AUTO-" + re.sub(r"[-\s]+", "_", basename).upper()

def ensure_registry() -> set:
    REGISTRY.parent.mkdir(parents=True, exist_ok=True)
    if not REGISTRY.exists():
        with REGISTRY.open("w", newline="") as f:
            csv.writer(f).writerow(REGISTRY_HEADER)
        return set()
    try:
        with REGISTRY.open(newline="") as f:
            reader = csv.DictReader(f)
            return {row["id"] for row in reader if row.get("id")}
    except Exception:
        return set()

def append_registry_row(op_basename: str, src_file: pathlib.Path) -> None:
    with REGISTRY.open("a", newline="") as f:
        csv.writer(f).writerow([
            auto_id(op_basename),
            classify_domain(str(src_file)),
            op_basename,
            "auto-scaffolded skeleton",
            "all",
            "(skeleton — fill in per test)",
            "(skeleton — fill in per test)",
            "(tbd)",
            "vitest",
            "medium",
            "pending",
            "",
            "",
        ])

def main() -> None:
    # TODO: update to your vitest.setup.ts location.
    setup_file = OPS_ROOT.parent / "vitest.setup.ts"
    existing_ids = ensure_registry()

    for src in OPS_ROOT.rglob("*.ts"):
        if should_skip(src):
            continue

        test_dir = src.parent / "__tests__"
        test_file = test_dir / (src.stem + ".test.ts")
        if test_file.exists():
            continue

        if has_consolidated_test(src):
            continue

        exports = resolve_exports(src)
        export_name = matches_basename(exports, src.stem)
        if not export_name:
            sys.stderr.write(
                f"generate-tests.sh: skipping stub for {src} — no matching "
                f"export found; create the test file manually if needed.\n"
            )
            continue

        test_dir.mkdir(parents=True, exist_ok=True)
        import_op = relative_import(test_file, src)
        import_setup = relative_import(test_file, setup_file)
        test_file.write_text(skeleton(export_name, import_op, import_setup))

        row_id = auto_id(src.stem)
        if row_id not in existing_ids:
            append_registry_row(src.stem, src)
            existing_ids.add(row_id)

main()
PY

exit 0
