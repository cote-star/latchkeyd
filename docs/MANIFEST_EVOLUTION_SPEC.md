# Manifest Evolution Spec

## Purpose

Describe how `latchkeyd` manifests evolved from the original single-model shape to the current mode-aware schema.

## Version 1

Version 1 manifests included:

- backend
- wrappers
- binaries
- secrets
- exec policies

Legacy policies without `mode` are interpreted as `handoff`.

## Version 2

Version 2 adds:

- explicit `mode` on policies
- optional `operationSet`
- top-level `operationSets`

That allows brokered policies to reference reusable allowlists without turning every policy into a large embedded DSL.

## Policy Shape

Current policy fields:

- `mode`
- `wrapper`
- `binary`
- `secrets`
- `operationSet`
- `description`

## Brokered Shape

Brokered policies point at an `operationSet`.

Example:

```json
{
  "mode": "brokered",
  "wrapper": "example-wrapper",
  "binary": "example-cli",
  "secrets": ["example-token"],
  "operationSet": "example-brokered-ops"
}
```

## Operation Sets

Current first-slice operation shape:

```json
{
  "operations": [
    {
      "name": "secret.resolve",
      "allowedSecrets": ["example-token"],
      "allowedResponseFields": ["secretName", "value", "lifetimeSeconds"]
    }
  ]
}
```

## Validation Rules

### Version 1

- may not declare `operationSets`
- may not reference `operationSet`

### Version 2

- brokered policies must reference an existing `operationSet`
- non-brokered policies may not reference `operationSet`
- operation allowlists must reference known secrets

## Migration Guidance

1. old manifests can still decode as `handoff`
2. new manifests should write explicit `mode`
3. brokered policies should move to version 2

The repo starter manifest already follows the version-2 shape.
