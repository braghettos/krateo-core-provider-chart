# krateo-core-provider-chart

Krateo PlatformOps **core-provider** blueprint — a fork of
[`krateoplatformops/core-provider-chart`](https://github.com/krateoplatformops/core-provider-chart)
packaged as a Krateo blueprint: the upstream Helm chart plus a `values.schema.json` and a
`CompositionDefinition`.

`core-provider` is the **composition engine** — it watches `CompositionDefinition`s, generates a
typed CRD per blueprint, and reconciles the resulting Compositions. It is the first thing the
installer brings up in bootstrap mode; every other component is a composition driven by it.

Part of the [krateo-installer](https://github.com/braghettos/krateo-installer) ecosystem.

## What it ships

| Path | Chart | OCI artifact |
|------|-------|--------------|
| `chart/` | `krateo-core-provider` (appVersion `2.0.0`) | `oci://ghcr.io/braghettos/krateo/krateo-core-provider` |
| `crd-chart/` | `krateo-core-provider-crd` | `oci://ghcr.io/braghettos/krateo/krateo-core-provider-crd` |
| `target-chart/` | `krateo-core-provider-target` | `oci://ghcr.io/braghettos/krateo/krateo-core-provider-target` |
| `kagent/chart/` | `krateo-core-provider-agent` | `oci://ghcr.io/braghettos/krateo/krateo-core-provider-agent` |

The deployment `chart/` also ships the composition-version `MutatingAdmissionPolicy` for the
management cluster. `target-chart/` ships that same policy for **remote deployment targets**:
install it into every cluster referenced by a `KubernetesTarget`. `kagent/chart/` is the
optional federated AI agent for blueprints/compositions.

> **Requirement:** core-provider 2.0.0 needs **Kubernetes ≥ 1.36** on the management cluster
> and every remote target (the GA `MutatingAdmissionPolicy` API). core-provider hosts no
> admission webhooks.

## How the installer consumes it

In **bootstrap mode** the umbrella pulls `krateo-core-provider` + `krateo-core-provider-crd` as
Helm subchart dependencies (from `oci://ghcr.io/braghettos/krateo`) so the engine is running
before any composition is reconciled. The shipped `CompositionDefinition` also lets
`core-provider` manage its own upgrades as a composition:

```yaml
apiVersion: core.krateo.io/v1alpha1
kind: CompositionDefinition
metadata:
  name: core-provider
  namespace: krateo-system
spec:
  chart:
    url: oci://ghcr.io/braghettos/krateo/krateo-core-provider
    version: "0.36.2"
```

## Local validation

```sh
helm lint chart
helm template smoke chart
```

## Release

Push a semver tag (`X.Y.Z`) — CI (`release-oci`) packages `chart/`, `crd-chart/`,
`target-chart/`, and the `kagent/chart/` agent, and publishes them all to
`oci://ghcr.io/braghettos/krateo`. The deployment chart's image tag defaults to its
`appVersion` (the core-provider release), so bump `chart/Chart.yaml` `appVersion` when
cutting a release tied to a new core-provider version.

## Links

- Installer umbrella: https://github.com/braghettos/krateo-installer
- Upstream: https://github.com/krateoplatformops/core-provider-chart
