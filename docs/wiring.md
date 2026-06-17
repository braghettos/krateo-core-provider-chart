# core-provider — composition wiring & operations (chart repo)

The `chart/values.yaml` surface, how the installer pins and wires core-provider, its dependencies,
and the real operational gotchas. Everything is traced to the chart; where a stale note disagrees
with the rendered chart, the chart wins.

## The `values.yaml` surface (`chart/values.yaml`)

The chart has three top-level workload blocks: the engine (top level), the **chart-inspector**
sidecar (`chartInspector.*`), and the **cdc** template settings (`cdc.*`) that core-provider stamps
into each per-composition controller.

### Engine (top level)

- **Exposure:** `service.type: ClusterIP`, `service.port: 80` (`values.yaml:41-43`). The engine has
  no public surface — it is an in-cluster controller; expose nothing by hand. `ingress.enabled:
  false` by default (`values.yaml:45-46`); HPA off (`autoscaling.enabled: false`,
  `values.yaml:80-84`).
- **Image:** `ghcr.io/braghettos/krateo-core-provider`, tag defaults to the chart `appVersion`
  (`values.yaml:7-11`, `deployment.yaml:36`). Bump `chart/Chart.yaml` `appVersion` to ship a new
  engine version.
- **Resources:** `resources: {}` by default — unset (`values.yaml:62`).
- **`env`:** rendered into the `<fullname>` ConfigMap and consumed via `envFrom`
  (`configmap.yaml:7-10`, `deployment.yaml:38-40`). Default: `CORE_PROVIDER_DEBUG: "false"`
  (`values.yaml:111-112`).
- `replicaCount: 1`, `nameOverride: "core-provider"` (`values.yaml:5,13`).

### chart-inspector sidecar (`chartInspector.*`)

A separate Deployment + ClusterIP Service on **port 8081** (`chart-inspector/service.yaml:11-13`)
that core-provider calls to inspect/expand blueprint charts. Image
`ghcr.io/braghettos/krateo-chart-inspector`, pinned `1.0.2` (`values.yaml:114-118`). Its own
`serviceAccount`, `service` (ClusterIP/80 target 8081), and `env: { HOME: /tmp }`
(`values.yaml:113-149`). The cdc ConfigMap wires controllers to it via
`URL_CHART_INSPECTOR: http://<chart-inspector>.<ns>.svc.cluster.local:8081/`
(`assets/cdc/configmap.yaml:16`).

### cdc template settings (`cdc.*`)

These do NOT run a controller in this release — they parametrize the Deployment/ConfigMap/RBAC that
core-provider stamps out **once per generated CRD** (the asset templates under `assets/cdc/`, mounted
into the engine at `/tmp/assets/`). Image `ghcr.io/braghettos/krateo-composition-dynamic-controller`,
pinned `1.0.2` (`values.yaml:139-141`). Key knobs in `cdc.env` (`values.yaml:225-238`):

- `COMPOSITION_CONTROLLER_DEBUG: "false"`, `COMPOSITION_CONTROLLER_WORKERS: "10"`.
- **`COMPOSITION_CONTROLLER_RESYNC_INTERVAL: "60s"`** — the load-bearing pace knob. Every spawned
  cdc re-discovers new CRDs on a resync (its RESTMapper refreshes on a cache miss). The installer's
  self-bootstrap advances to the next dependency level on this resync, so `60s` makes the umbrella
  hands-off in minutes instead of ~3m/level at the upstream `3m` default (`values.yaml:228-238`).
- `cdc.metrics.enabled: false` — when true, mounts the cdc Service asset and sets the metrics port
  (`values.yaml:143-145`, `deployment.yaml:62-66`, `cdc-service.yaml`).

## What needs k8s ≥ 1.36

core-provider 2.0.x serves the composition-version stamp via a GA `MutatingAdmissionPolicy`
(`compositions-version-policy.yaml`), NOT an admission webhook — so there is no webhook server,
serving cert, or `MutatingWebhookConfiguration`. That API is GA only from **Kubernetes 1.36**
(`compositions-version-policy.yaml:5-13`, `README.md:30-34`). The management cluster AND every remote
deployment target must be ≥ 1.36.

## Dependencies (what must exist around core-provider)

- **The `krateo-core-provider-crd` Composition** (the two static `core.krateo.io` CRDs from
  `crds-subchart/`) — deployed as its own Composition. The app chart deliberately does NOT bundle it
  (`README.md:25`); see [overview.md](overview.md).
- **Cluster RBAC** — the chart ships its own engine ClusterRole + binding with broad authority over
  `core.krateo.io`, CRDs, deployments, RBAC objects, serviceaccounts, secrets (read),
  `composition.krateo.io/*`, configmaps, services and events (`clusterrole.yaml:5-86`); needed
  because the engine creates the generated CRDs and per-composition cdc Deployments/RBAC.
- **k8s ≥ 1.36** on the management cluster (GA `MutatingAdmissionPolicy`).
- **For remote targets:** install the `target-chart` (`krateo-core-provider-target`) into every
  cluster referenced by a `KubernetesTarget` — it ships the composition-version policy so
  compositions created there get stamped (`README.md:30-37`). Each per-composition cdc also gets its
  own ClusterRole (`assets/cdc/rbac/clusterrole.yaml`) granting CRD read, `composition.krateo.io/*`,
  RBAC, namespaces, secrets, and `compositiondefinitions` read.

## How the installer wires it

In **bootstrap mode** the [krateo-installer](https://github.com/braghettos/krateo-installer) umbrella
pulls `krateo-core-provider` + `krateo-core-provider-crd` as Helm subchart dependencies (from
`oci://ghcr.io/braghettos/krateo`) so the engine is running before any Composition is reconciled
(`README.md:56-61`). The shipped self-managing `CompositionDefinition` (`compositiondefinition.yaml`)
then lets core-provider manage its own upgrades as a composition. The deployed chart version is
readable from `CompositionDefinition.spec.chart.version` (the tag at which to fetch THIS repo's
docs); the `crds-subchart` is pinned separately.

## Gotchas

- **Resync interval drives self-bootstrap pace.** `COMPOSITION_CONTROLLER_RESYNC_INTERVAL: "60s"`
  (down from upstream `3m`) is what makes the umbrella self-bootstrap finish in minutes. Each cdc
  re-discovers new CRDs only on its resync — raise it and dependency-level advancement slows
  proportionally (`values.yaml:228-238`).
- **Stale CRD-discovery cache → no new Compositions.** When a new component's CRD is published, an
  already-running cdc may keep emitting nothing until its RESTMapper cache refreshes; live umbrella
  upgrades have needed a **cdc restart** to clear the stale discovery cache before Compositions
  resume. If core-provider/cdc stops emitting a component's Composition after a CRD change, restart
  the cdc.
- **k8s < 1.36 breaks the engine.** The `MutatingAdmissionPolicy` (and the version stamp it applies)
  needs the GA API; on an older cluster the policy won't install and composition-version labelling
  fails. There is no webhook fallback on the 2.0.x line.
- **Remote targets need the `target-chart` AND a reachable kubeconfig.** A `KubernetesTarget` points
  at a Secret holding the target's kubeconfig (`spec.kubeconfigRef`); the target cluster must also
  have the `target-chart` policy installed and be ≥ 1.36, or compositions created there won't be
  stamped. `status.target.connectionStatus` shows `Down` when the target is unreachable.
- **Don't bundle the CRD subchart.** Adding `crds-subchart` as a dependency of `chart/` makes the app
  release try to own the static CRDs and collide with the `krateo-core-provider-crd` release. CRDs
  ship as their own Composition (`README.md:25`).
- **The CRDs are generated, not hand-written.** `crds-subchart/templates/*.yaml` are produced by the
  code repo's CI and pushed here on each release tag — edit the Go types in the code repo, not these
  files (`README.md:21-28`).

## See also

- [overview.md](overview.md) — chart layout, the self-managing CompositionDefinition, what gets
  deployed.
- [crds.md](crds.md) — the CompositionDefinition + KubernetesTarget CRD fields.
- Code repo runtime view: `braghettos/krateo-core-provider`
  [`docs/llms.txt`](https://github.com/braghettos/krateo-core-provider/blob/main/docs/llms.txt)
  (crdgen pipeline, the cdc reconcile loop, remote-target connection).
