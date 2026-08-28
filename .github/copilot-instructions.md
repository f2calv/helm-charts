# Copilot Instructions

## Instruction Files

Detailed conventions live in scoped instruction files under
`.github/instructions/`, auto-applied by file type:

| File | Applies to | Covers |
| --- | --- | --- |
| `helm.instructions.md` | `charts/**` | Helm chart authoring conventions, values.schema.json, dependency wiring |

The conventions below always apply, regardless of the file being edited.

## Misc

* When detecting new chart conventions or patterns, add them to
  `.github/instructions/helm.instructions.md` and apply them retroactively where
  appropriate.
