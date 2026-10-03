# Architecture decision records

Applies to: all RIoT2 repositories.

An ADR records one significant decision: the context, the decision, and its consequences. ADRs are
append-only. To change a decision, add a new ADR that supersedes the old one and update the old
one's status line. Don't rewrite history.

## When to write one

- A choice that constrains more than one repository (contracts, security model, runtime, tooling).
- A choice that someone (human or AI) is likely to "fix" later without knowing why it was made.
- Accepting or rejecting a proposal from a platform review.

## How

1. Copy [0000-template.md](0000-template.md) to `NNNN-short-kebab-title.md` using the next free number.
2. Fill it in. Keep it under one screen where possible; link to designs instead of copying them.
3. Add a row to the index below.

## Index

| ADR | Title | Status |
|---|---|---|
| [0001](0001-documentation-structure.md) | Documentation structure and AI instruction files | Accepted |
| [0002](0002-isolated-network-security-model.md) | Isolated single-user network security model | Accepted |
| [0003](0003-elsa-sole-automation-engine.md) | Elsa 3 is the only automation engine | Accepted |
