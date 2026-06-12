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
| `chart/` | `core-provider` (appVersion 0.26.1) | `oci://ghcr.io/braghettos/krateo/core-provider` |
| `crd-chart/` | `core-provider-crd` | `oci://ghcr.io/braghettos/krateo/core-provider-crd` |

## How the installer consumes it

In **bootstrap mode** the umbrella pulls `core-provider` + `core-provider-crd` as Helm subchart
dependencies (from `oci://ghcr.io/braghettos/krateo`) so the engine is running before any
composition is reconciled. The shipped `CompositionDefinition` also lets `core-provider` manage
its own upgrades as a composition:

```yaml
apiVersion: core.krateo.io/v1alpha1
kind: CompositionDefinition
metadata:
  name: core-provider
  namespace: krateo-system
spec:
  chart:
    url: oci://ghcr.io/braghettos/krateo/core-provider
    version: "0.35.2"
```

## Local validation

```sh
helm lint chart
helm template smoke chart
```

## Release

Push a semver tag (`X.Y.Z`) — CI packages `chart/` and `crd-chart/` and publishes both to
`oci://ghcr.io/braghettos/krateo`.

## Links

- Installer umbrella: https://github.com/braghettos/krateo-installer
- Upstream: https://github.com/krateoplatformops/core-provider-chart
