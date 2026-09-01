# Copilot Instructions

## Instruction Files

Detailed conventions live in scoped instruction files under
`.github/instructions/`, auto-applied by file type:

| File | Applies to | Covers |
| --- | --- | --- |
| `helm.instructions.md` | `charts/**` | Helm chart authoring conventions, values.schema.json, dependency wiring |

The conventions below always apply, regardless of the file being edited.

## Public Repository Confidentiality

* Treat every non-public repository's identity and contents as confidential, even when they appear in the local workspace, conversation context, diffs, logs, or tool output.
* Never publish private repository names, URLs, owner/repository coordinates, branches, file paths, architecture, deployment details, or inferred existence in tracked files, commit messages, issues, pull request titles/descriptions/reviews/comments, release notes, workflow annotations, examples, or other public-facing content.
* Describe required relationships generically (for example, "private GitOps repository" or "internal service") and supply private coordinates only through secrets, repository variables, or caller-provided values.
* Before creating or updating public GitHub content, review the proposed text and metadata for private identifiers and implementation details.

## Misc

* When detecting new chart conventions or patterns, add them to
  `.github/instructions/helm.instructions.md` and apply them retroactively where
  appropriate.
