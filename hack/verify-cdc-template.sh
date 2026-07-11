#!/usr/bin/env bash
# Golden + render test for the doubly-templated CDC Deployment asset (chart/assets/cdc/deployment.yaml).
#
# That asset is rendered TWICE: first by Helm at install (resolving .Values.cdc.* and the {{ "{{" }}
# escapes), then by core-provider's text/template engine per CompositionDefinition (resolving
# {{ .resource }}, {{ .workers }}, ...). A whitespace slip in either layer silently breaks every CDC.
#
#   STAGE 1 (golden): snapshot the Helm-rendered RUNTIME template so any change to the escaping is
#                     caught in review.
#   STAGE 2 (render): feed that runtime template back through Helm's `tpl` (the SAME text/template +
#                     sprig engine core-provider uses) with real value sets and assert each renders a
#                     VALID Deployment — catching a whitespace break that only surfaces at render time.
#
#   ./hack/verify-cdc-template.sh           # verify (CI)
#   ./hack/verify-cdc-template.sh --update  # regenerate the stage-1 golden after an intentional change
set -euo pipefail
cd "$(dirname "$0")/.."
GOLDEN="hack/golden/cdc-runtime-template.yaml"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
cp -r chart "$work/chart"
sed -i.bak 's/CHART_VERSION/0.0.0/g; s/APP_VERSION/0.0.0/g' "$work/chart/Chart.yaml" && rm -f "$work/chart/Chart.yaml.bak"

extract() { # render the chart and pull the CDC deployment runtime-template out of its ConfigMap
  helm template golden "$work/chart" | python3 -c '
import sys,yaml
for d in yaml.safe_load_all(sys.stdin):
    if d and d.get("kind")=="ConfigMap" and d.get("metadata",{}).get("name","").endswith("-cdc-deployment"):
        print(list(d["data"].values())[0], end=""); break
'
}

rendered="$(extract)"

# ---- STAGE 1: golden snapshot ------------------------------------------------------------------
if [[ "${1:-}" == "--update" ]]; then
  printf '%s' "$rendered" > "$GOLDEN"; echo "updated $GOLDEN"; exit 0
fi
[[ -f "$GOLDEN" ]] || { echo "missing $GOLDEN — run with --update" >&2; exit 1; }
if ! diff -u "$GOLDEN" <(printf '%s' "$rendered"); then
  echo "ERROR: CDC runtime template drifted from golden. If intentional: ./hack/verify-cdc-template.sh --update" >&2
  exit 1
fi
echo "OK (stage 1): CDC runtime template matches golden"

# ---- STAGE 2: render the runtime template the way core-provider does, assert valid Deployment ---
helper="$work/helper"; mkdir -p "$helper/templates"
printf 'apiVersion: v2\nname: rt\nversion: 0.0.0\n' > "$helper/Chart.yaml"
printf '%s' "$rendered" > "$helper/rt.yaml"
# core-provider renders assets/cdc/deployment.yaml with `.` = the per-CD value map; `tpl` mirrors that.
echo '{{ tpl (.Files.Get "rt.yaml") .Values.ctx }}' > "$helper/templates/out.yaml"

BASE='"apiGroup":"composition.krateo.io","apiVersion":"v0-1-0","resource":"benchapps","namespace":"bench-ns-01","name":"benchapps-v0-1-0-controller","serviceAccountName":"sa","api_ref_name":""'
check() { # <label> <ctx-json> ; render, assert one valid Deployment, print its CDC args
  local label="$1" ctx="$2"
  helm template rt "$helper" --set-json "ctx={$ctx}" | python3 -c '
import sys,yaml
docs=[d for d in yaml.safe_load_all(sys.stdin) if d]
deps=[d for d in docs if d.get("kind")=="Deployment"]
assert len(deps)==1, "expected one Deployment, got kinds: "+str([d.get("kind") for d in docs])
args=deps[0]["spec"]["template"]["spec"]["containers"][0].get("args",[])
print("  args:", " ".join(args))
' || { echo "ERROR (stage 2, $label): runtime template did not render a valid Deployment" >&2; exit 1; }
  echo "OK (stage 2, $label)"
}

check "unset (opt-in defaults omitted)"       "$BASE"
check "tuned per-Kind"                          "$BASE,\"workers\":64,\"resyncInterval\":\"1h\",\"resources\":{\"requests\":{\"memory\":\"512Mi\"}}"
echo "OK: CDC template golden + render checks passed"
