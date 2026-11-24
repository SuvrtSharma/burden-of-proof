# ADR-0011: God's Hand is an umbrella toolkit; Lean 4 is the first track

- **Status:** Accepted
- **Date:** 2026-11-07
- **Deciders:** project owner
- **Cites claims:** none

## Context

The KT document describes one tool: a checker for agents' claims, centred on
Lean 4. The owner's real aim is wider. They want tools and skills that let AI
agents build new software, modify codebases and **migrate legacy software to
new stacks** safely, with agents able to verify their own claims about those
changes (for example "this rewrite behaves the same").

## Decision

- This repo is an **umbrella of tracks**. Each track explores one way of
  turning agents' claims into evidence. A track that works is distilled into
  a reusable tool, a Claude Code skill (`skills/`), or a server any agent can
  call.
- **Track 1, and the only active one now, is Lean 4.** It asks what Lean 4
  can model in a modern SaaS system, and which orthodox and unorthodox
  optimisations keep their meaning.
- Later tracks, each opened by its own ADR when started: migration and
  rewrite equivalence for legacy code, access control (SMT), concurrency
  (TLA+/P), static data-flow.
- Shared pieces (claim records, guarantee register, evidence rules) are
  common to every track. ADRs 0002, 0004, 0005, 0008 and 0010 apply
  repo-wide.

## Alternatives considered

- **One repo per tool from the start:** too early. The tools share the
  claim format and the evidence discipline, and the boundaries aren't known
  yet.

## Consequences

- Agents must not start a new track on their own. Starting one needs an ADR
  approved by the owner.
- The README describes the umbrella. Each track keeps its own detail in its
  own folder or ADRs.

## Revisit when

A track is mature enough to be published on its own, at which point it gets
split out.
