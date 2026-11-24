# ADR-0029: Public name Burden of Proof, and a curated public repo

- **Status:** Accepted. Amends ADR-0013.
- **Date:** 2026-11-24
- **Deciders:** project owner (approved 2026-11-24)
- **Cites claims:** none

## Context

ADR-0013 gave the project a placeholder name, God's Hand, in a private repo.
The owner wants others to be able to use the tools and skills, and asked for a
sensible public name. Three constraints shape what can be published:

- **Locked files can't change.** One byte of a locked spec, lakefile or
  toolchain file voids every proof until the owner reviews it again
  (ADR-0004). Several mention `godshand`.
- **Findings go to an author first** (ADR-0023, decision 5). Some part 2
  reading notes haven't gone to Precise Ledger Pro's author yet.
- **Their configuration is never used or repeated.** Some recorded Java logs
  print it.

## Decision

1. **The public name is Burden of Proof.** The repository is
   `burden-of-proof`, and the Python package and CLI are `burden_of_proof`.
   It is licensed Apache-2.0.
2. **The public repo starts with a fresh, curated history.** God's Hand stays
   private as the lab notebook, and remains the source of record.
3. **Left out of the public copy:**
   - the daily journal
   - the original design notes (`KT.md`)
   - the part 2 reading notes and draft issues and pull requests
   - early part 2 runs (`evidence/plp`, apart from the Haskell reproduction
     already published)
   - every Java log that prints the project's configuration

   Passages about unsent findings or that configuration are redacted in place,
   marked as redacted.
4. **Kept byte for byte:**
   - the locked specs, their lakefiles, toolchain files and Lake manifests
   - all recorded evidence
   - the part 2 Java harness names

   These still say `godshand`, and the README explains why.
5. **The public repo adds** two Claude Code skills (`check-lean-claim`,
   `check-optimisation-claim`) and a reviewer agent (`claim-reviewer`).

## Alternatives considered

- **Publish the full history:** every dead end in public, but also everything
  above that mustn't be, in every past commit.
- **Rename the locked files too:** a clean name everywhere, at the cost of
  re-locking both specs and re-running every proof. Possible later, as an
  owner action.
- **Keep `godshand` as the package name:** no code changes, but the private
  name would appear in every command.

## Consequences

- There are two repos to keep in step. New results land in God's Hand first.
  Publishing them is a deliberate copy, with the same scrub.
- Some public documents cite private files. Each says so.

## Revisit when

- The owner re-locks the specs under the new name.
- Precise Ledger Pro's author has the remaining notes. Then the redacted parts
  can be published.
