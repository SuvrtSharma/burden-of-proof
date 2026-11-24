# ADR-0001: Record architecture decisions as ADRs

- **Status:** Accepted
- **Date:** 2026-11-07
- **Deciders:** project owner
- **Cites claims:** none

## Context

Agents will do much of the work in this repo, and they start every session
without memory. They need a durable, local answer to "why is it like this?".
Otherwise they re-argue settled choices or quietly drift away from them. The
project's purpose is to keep design documents from drifting away from the
truth, so its own documents have to meet that standard first.

## Decision

- Decisions go in `docs/adr/NNNN-kebab-title.md`, using
  [the template](0000-template.md).
- ADRs are append-only: a decision changes only through a new ADR that
  supersedes the old one.
- docs/KT.md (in the private design notes) is the original statement of intent. Where an ADR
  disagrees with it, the ADR wins, and KT.md gets a short note pointing to it.
- Once claim records exist, an ADR cites claim ids instead of restating facts.
- Questions that aren't settled yet live in
  [open-questions.md](../open-questions.md). They become ADRs once answered.

## Alternatives considered

- **Only the KT doc, edited in place:** loses the reasoning behind each
  change, and can't be cited at a fine grain.
- **A wiki or other external tool:** agents can't read it offline, and CI
  can't check it.

## Consequences

- Agents read the ADR index before proposing structural changes.
- One more file per decision. That is a small cost.

## Revisit when

The number of ADRs makes the index hard to scan (roughly 50 or more).
