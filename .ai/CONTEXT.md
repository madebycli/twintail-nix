# AI Context Route

```yaml
schema_version: 1
context_repo: https://github.com/madebycli/master-context
project_id: twintail-nix
source_repo: https://github.com/madebycli/twintail-nix
context_root: projects/twintail-nix/
entrypoint: projects/twintail-nix/INDEX.md
```

## Mandatory AI behavior

Use this exact route. Validate against `REGISTRY.yaml`, read the declared entrypoint first, do not scan sibling project folders, reconcile durable context with verified repository reality before declaring work complete, and archive reusable prompts/plans/handoffs under `prompts/twintail-nix/` when possible.
