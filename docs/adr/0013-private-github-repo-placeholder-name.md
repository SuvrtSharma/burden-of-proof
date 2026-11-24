# ADR-0013: Private GitHub repo under a placeholder name

- **Status:** Accepted
- **Date:** 2026-11-07
- **Deciders:** project owner
- **Cites claims:** none

## Context

The project needs version control and a remote. Its findings will eventually
be published as tools and skills, but it is early, and its name isn't decided.

## Decision

- Git repo, hosted on GitHub as a **private** repository named `gods-hand`
  under the owner's account.
- "God's Hand" is a **placeholder** name. Renaming later is expected (GitHub
  redirects renamed repos).
- Commits and PRs carry **no AI attribution**.

## Consequences

- Nothing is public. Going public is a separate, explicit decision by the
  owner, made after checking that nothing private is in the history.

## Revisit when

The project gets a real name, or the owner decides to publish.
