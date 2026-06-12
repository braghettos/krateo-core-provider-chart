# `krateo-core-provider-agent` — federated specialist agent

The Krateo blueprints/composition-engine expert: manages CompositionDefinitions, compositions and the marketplace. Knows braghettos/core-provider + braghettos/krateo-core-provider-chart.

Per the [/kagent standard](https://github.com/braghettos/krateo-autopilot/blob/main/AGENTS-VERSIONING.md)
it is **component-scoped** and knows its component from this chart's `Chart.yaml` `sources`
(`braghettos/core-provider`, `braghettos/krateo-core-provider-chart`), read via github MCP tools.
Reachable only through the `krateo-autopilot` orchestrator (registered via `extraAgents`). Published
to `oci://ghcr.io/braghettos/krateo/krateo-core-provider-agent` (pinned `0.1.0`).
