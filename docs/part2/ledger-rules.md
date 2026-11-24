# Production ledger rules, from outside sources

**Status: v2, approved by the owner on 2026-11-18 ([ADR-0025](../adr/0025-part2-ledger-rules-and-project.md)).** Version 1 was
reviewed by the owner the same day. Every point of that review is applied here;
the changes are listed at the end.

These rules come from published practice, standards, regulation and case law,
not from Precise Ledger Pro's code or paper, and none is softened to fit them.
Once approved, they are the basis of the part 2 Lean spec (ADR-0024: fixed
amounts first, then interest). Rules marked ⚠ rest on a secondary source or on
reasoning alone, as noted.

Each rule has a strength:
- **MUST:** a source requires it, or the ledger is wrong without it.
- **CONTRACT:** the loan agreement or a written policy sets the details, which
  must then be applied deterministically.
- **PRODUCTION:** required of a production ledger, but outside the mathematical
  model. It's checked by design review and by tests of the running system.

## Inputs every rule assumes

A ledger's outcome depends on more than its events. These are inputs, recorded
and versioned with the ledger. "The same inputs" in any rule below means all of
them:
1. the events, each with its event id, business (effective) date and
   processing (posting) sequence;
2. the policy versions in force: allocation order, rounding mode, posting
   frequency, day-count convention, and which events may be corrected
   retroactively;
3. the rate schedule and the business-day calendar;
4. the evaluation date. Accrual "through today" requires an explicit cut-off
   date or an accrual event; nothing reads the wall clock.

## A. Money

**LR1. Amounts are exact, in each currency's own scale, within stated limits.
(MUST)**
- Every amount is exact: an integer count of the currency's minor unit (this
  project's choice), or an exact fixed-point decimal with a stated scale. Never
  binary floating point.
- Each ledger states its currency and that currency's scale: USD 2, JPY 0,
  KWD 3. Amounts are kept to that scale; a non-decimal currency needs its own
  rule (ISO 4217, ⚠ secondary sources: [Straumur](https://docs.straumur.is/resources/currencies-minor-units),
  [Datatrans](https://docs.datatrans.ch/docs/currency-codes)).
- Each ledger states its maximum amount and what happens beyond it: the
  operation is rejected. Values never wrap, saturate or lose precision.
- *Test:* every amount is an exact multiple of the ledger currency's minor unit
  (0.01 USD, 1 JPY, 0.001 KWD), checked per currency. Amounts at the limit
  succeed; amounts beyond it are rejected with an error.

**LR2. Rounding has a stated mode, a stated posting frequency and a stated
residual policy. (MUST; the details are CONTRACT)**
- Rounding happens when an amount is posted, to the currency's scale, in the
  stated mode (for example half-up or half-even).
- **Posting frequency is part of the policy.** Rounding each daily accrual and
  rounding one monthly total can give different results, so the policy states
  which it is. Unrounded accrual carried between postings is recorded state.
- **The policy names where fractional residuals go:** carried to the next
  posting, or written to a named rounding-difference account. "Loses nothing"
  is replaced by that explicit policy.
- **Splits conserve the amount** and give any remainder to parts in a stated,
  deterministic order.
- *Source:* this follows from LR1 and LR15 ⚠ (no single external rule quoted).
- *Test:*
  - a split of N minor units sums to exactly N, and the remainder lands where
    the policy says, in every run;
  - posted interest plus the carried residual equals the exact accrual for the
    period;
  - daily and monthly posting policies are each tested against their own
    expected totals.

## B. Entries and balances

**LR3. A posted entry is never changed or deleted. (MUST)**
- Order of record is the **posting sequence**: the order entries were
  committed. Business dates may be earlier than the posting date, because late
  events are normal (LR11).
- The ledger answers two questions and never confuses them:
  - *what we reported then*: balances as of a posting sequence number, which
    never change;
  - *what we now calculate for that business date*: balances by effective date
    under the current, corrected history.
- *Sources:*
  - Stripe's ledger records "cannot be deleted or modified"
    ([Stripe engineering, Ledger](https://stripe.dev/blog/ledger-stripe-system-for-tracking-and-validating-money-movement)).
  - Fowler: don't change entries "when they are closed, or booked"
    ([Accounting Entry](https://www.martinfowler.com/eaaDev/AccountingEntry.html)).
  - For broker-dealers, SEC Rule 17a-4 requires non-rewriteable,
    non-erasable records, or an audit trail able to recreate any altered
    original ([SEC fact sheet 34-96034](https://SEC.GOV/files/34-96034-fact-sheet.pdf),
    [FINRA](https://www.finra.org/rules-guidance/key-topics/books-records)).
    That rule is cited as a standard, not as law for a loan servicer ⚠.
- *Test:* ordered by posting sequence, the entries before any operation are an
  unchanged prefix of the entries after it, field for field. A balance reported
  as of sequence number S is the same when asked again later.

**LR4. Every balance is derived from auditable postings. (MUST)**
- A balance is the sum of the postings in scope, per component. Any stored
  running balance equals that sum at its position.
- **Opening balances are postings too:** an opening-balance event with a source,
  or an explicitly reconciled migration input with its reconciliation recorded.
  No balance appears from nowhere.
- *Source:* Modern Treasury: "computing a balance from a log of transactions",
  so that balances "can be reconstructed as of any date"
  ([Accounting for developers, part I](https://www.moderntreasury.com/journal/accounting-for-developers-part-i)).
- *Test:* recompute every balance from postings (by posting sequence for "then",
  by effective date for "now") and compare it with what the system reports.
  Every opening balance traces to an opening-balance event or a migration
  record.

**LR5. Every transaction balances, in one currency or valuation basis. (MUST
at the accounting boundary)**
- A transaction's entries net to zero across accounts, per currency or on a
  stated valuation basis with its exchange rates recorded. Adding amounts in
  different currencies without a stated basis is meaningless and is rejected.
- If the counterpart (cash, interest income) lives in another system, the
  reconciliation is defined and tested (LR22). It isn't left to design review.
- *Sources:* Modern Treasury: debits equal credits, or the system has "created
  or lost money out of nothing" (as above). Stripe's ledger is "based on
  double-entry bookkeeping" (as above).
- *Test:* per transaction and per currency, the sum over accounts is zero. If
  the counterpart is external, run the LR22 reconciliation on the same events.

**LR6. Every entry is fully explained. (MUST)**
- Every entry names the event that triggered it.
- A correction entry also links to the original entries or events it corrects.
  A single source-event id doesn't explain a correction caused by a different,
  late event, so both links are kept.
- *Source:* Stripe reports explaining more than 99.9999% of money movement
  (as above).
- *Test:* every entry's trigger exists. Every correction links to at least one
  original, and following the links accounts for the correction amount.

## C. Corrections

**LR7. Corrections are new entries that offset exactly what they claim to.
(MUST)**
- Originals stay (LR3).
- A reversal posts offsetting entries for exactly the amounts and accounts of
  the originals it names.
- A difference adjustment posts, per account, exactly the gap between the
  recorded and the corrected value.
- *Sources:* Fowler's [Reversal Adjustment](https://martinfowler.com/eaaDev/ReversalAdjustment.html)
  and [Difference Adjustment](https://www.martinfowler.com/eaaDev/DifferenceAdjustment.html);
  Stripe: "we have to revert and reprocess prior operations" (as above).
- *Test:*
  - preserving the originals is necessary, not sufficient;
  - for each reversal, the reversal amounts per account equal the negated
    amounts of the originals it links to;
  - for each adjustment, the amount equals the corrected value minus the
    recorded value.

**LR8. After an eligible late or corrected event, all state ends where on-time
processing would have put it. (MUST; this is the oracle)**
- **Scope.** This applies to events the policy marks as eligible for retroactive
  correction, within open periods.
  - In a **closed period**, the correction is posted in the current open period
    with its original business date recorded. Closed-period figures are never
    restated.
- **Same-day order.** Events with the same business date are ordered by a
  stated rule: for example, accruals at start of day, then by business
  timestamp, then by event id. Never by arrival.
- **Dependencies.** A correction that depends on another (for example, a
  reversal of a late payment) is processed after it. A correction whose target
  doesn't exist yet is rejected or held, by policy.
- **What is compared: all state that affects future behaviour.** That means
  balances per component, accrued-but-unposted interest, carried rounding
  residuals, unapplied funds, each event's total effect and the status of each
  payment (LR20). Comparing balances alone isn't enough.
- *Source:* Fowler's Retroactive Event defines the incorrect reality, the
  correct branch (on-time processing) and the corrected reality, which should
  equal the correct branch ([Retroactive Event](https://martinfowler.com/eaaDev/RetroactiveEvent.html)).
  Our owner's decision (ADR-0024) fixed the minimum comparison; this version
  widens it to all forward-looking state.
- *Test:* for any sequence of eligible events in open periods, the state above
  equals a full rebuild that processes all live events in the same-day order
  from the start.

**LR9. Reversing an event removes all its consequences. (MUST)**
- Its direct entries are offset (LR7).
- Everything computed from the balances it changed is corrected (LR8):
  interest accrued on them, and later payments' allocation.
- The reversal links to the event it reverses (LR6), and an event can be
  reversed at most once (LR20).
- *Test:* reverse(E) gives a full rebuild with E removed. A second reversal of E
  is rejected.

**LR10. The outcome depends on business dates, the same-day rule and event
identity, not on arrival order. (MUST, within LR8's scope)**
- *Test:* shuffle the arrival order of eligible events and compare all LR8
  state. This follows from LR8 ⚠ (no separate source).

## D. Payments and interest

**LR11. A payment counts from its effective date, not from when it was
processed. (MUST)** For consumer credit secured by a home, Regulation Z
requires crediting a periodic payment "as of the date of receipt"
([12 CFR 1026.36(c)(1)(i)](https://www.law.cornell.edu/cfr/text/12/1026.36)).
- *Test:* a payment processed late gives the same LR8 state as the same payment
  processed on its date.

**LR12. A payment pays the interest accrued to its date first, then principal.
(CONTRACT; the default is the US Rule)**
- Interest is computed to the date of each payment. The payment goes to that
  interest first, and any surplus to principal. Unpaid interest isn't
  compounded.
- *Source:* *Story v. Livingston*, 38 U.S. 359 (1839), quoted in later opinions
  as "the creditor shall calculate interest whenever a payment is made"
  (⚠ secondary: [Jacobs v. Ballenger](https://law.counselstack.com/opinion/jacobs-v-ballenger-ind-1892)).
- A contract may put fees first; the order is fixed and documented.
- *Test:* nothing goes to principal while interest accrued to the payment date
  is unpaid, and interest is never charged on interest.

**LR13. Daily interest is principal times rate times the day-count fraction.
(MUST; the convention is CONTRACT)**
- For Actual/365 Fixed, the year fraction is the actual days divided by 365,
  leap years included (2006 ISDA Definitions §4.16(d), via
  [OpenGamma Strata](https://strata.opengamma.io/day_counts/)).
- A day's interest uses that day's principal under LR8, including late payments
  effective before it.
- Rounding and posting follow LR2.
- *Test:* each accrual equals exact principal × rate × days / 365, then LR2.

**LR14. Rates come from a complete, unambiguous, versioned schedule. (MUST)**
- **Lookup:** the rate on a date is the one with the latest start on or before
  that date.
- **Missing initial rate:** a date before the first rate has no rate, so
  accrual on it is an error, never a silent zero.
- **Duplicate start dates:** two rates with the same start are rejected when
  entered.
- **Superseded versions:** a correction to the schedule is a new version with
  its own recording time. Retroactive application follows LR8.
- **Change-day timing:** the policy states whether a rate starting on day D
  applies to day D's accrual. The default: it applies from D's accrual.
- **Storage order never resolves a conflict.**
- This rule is derived from what an effective date means ⚠ (no external source
  quoted).
- *Test:*
  - the same schedule stored in any order gives the same accruals;
  - a missing initial rate and a duplicate start are each rejected;
  - a rate starting on D is used for D's accrual, under the default policy.

## E. Processing

**LR15. Money is conserved at every step. (MUST)**
- **At allocation time:** payment = sum of allocations + unapplied amount, to
  the minor unit.
- **Later:** unapplied funds stay on the ledger until applied, refunded or
  returned. Each of those is a lifecycle event (LR20) with its own entries.
- Invalid input is rejected with an error, never coerced to zero.
- *Source:* Stripe's clearing check, "Did the fund flow complete correctly?"
  (as above), and LR5's "created or lost money". Rejecting rather than
  coercing is ⚠ by reasoning.
- *Test:*
  - the identity above holds for every payment;
  - every unapplied amount is later accounted for by an application, a refund
    or a return, or is still shown as unapplied;
  - a malformed amount gives an error, not a zero posting.

**LR16. Business events are deduplicated by a complete, scoped key, durably.
(MUST)**
- The key is scoped, for example by loan and event type, and compared as a
  whole.
- Sharing one component of a composite key is fine; two distinct valid full
  keys both post.
- The same full key with the same content posts once. A retry returns the
  original result.
- The same full key with different content fails with an error, never a silent
  skip.
- Deduplication of business events is durable. It survives the expiry of any
  API retry cache, because a retried business event can arrive days later.
- *Source:* Stripe's idempotent requests: a retry returns the saved response,
  and mismatched parameters are an error
  ([Stripe API](https://docs.stripe.com/api/idempotent_requests)). Stripe
  prunes API keys after 24 hours, which is why business-event deduplication
  can't rely on the API layer alone.
- *Test:*
  - the same event twice gives one posting;
  - the same full key with changed content gives an error;
  - two events sharing some key components but differing in the full key both
    post;
  - a duplicate arriving after any cache expiry is still caught.

**LR17. The same inputs give the same ledger. (MUST)** "The same inputs" is
everything listed under *Inputs every rule assumes*: events, policy versions,
rates, calendars, rounding rules and the evaluation date. Amounts never depend
on the wall clock, the machine or the run. Processing timestamps may differ,
but no amount may depend on them.
- *Sources:* Stripe grounds correctness in a model allowing a "mathematical
  proof of correctness" (as above); replay reproduces state (Fowler, Retroactive
  Event, as above).
- *Test:* run the same inputs twice, at different wall-clock times, and compare
  every amount and balance. Change only the evaluation date, and only accruals
  after the old cut-off change.

**LR18. Concurrent work on a ledger is safe. (PRODUCTION; outside the first
model)**
- Conflicting updates to one loan are serialised or rejected: neither update is
  lost.
- Retries are safe through LR16.
- An operation is acknowledged only after it is durable (LR19).
- *Test:* concurrent payments and corrections on one loan in a running system
  produce a state equal to some serial order, with no lost updates.

## F. Production requirements beyond the model

**LR19. Posting is atomic and recoverable. (PRODUCTION)**
- An accepted operation commits its journal entries, allocations and
  deduplication record together, or none of them.
- A crash or timeout leaves an outcome the caller can recover: a retry with the
  same key either completes the operation or returns its committed result.
- *Source:* PostgreSQL describes a transaction as "a single, all-or-nothing
  operation". Its effects are "logged in permanent storage ... before the
  transaction is reported complete", and partial state is "invisible to other
  transactions until the transaction completes"
  ([PostgreSQL, Transactions](https://www.postgresql.org/docs/current/tutorial-transactions.html)).
- *Test:* kill the process at each step of posting, then retry. Afterwards
  there are no partial entries, and exactly one posting per key.

**LR20. Payments follow a defined lifecycle. (PRODUCTION; the states are
CONTRACT)**
- The states are defined, as applicable: pending, received, settled, returned,
  refunded, unapplied.
- Only permitted transitions are allowed, each with its own entries.
- Reversals can't be duplicated or exceed the original. A payment can be
  reversed or refunded at most up to its amount, once per portion.
- *Test:* every disallowed transition is rejected. Total reversals and refunds
  never exceed the payment.

**LR21. Only valid, authorised postings are accepted. (PRODUCTION)**
- Every posting is checked for account existence and status, ownership (the
  account belongs to the loan), currency (it matches the account), and the
  caller's permission to post or correct.
- *Test:* a posting with each of these wrong is rejected, and the rejection
  posts nothing.

**LR22. The ledger reconciles with the outside world. (PRODUCTION)**
- The ledger is matched against bank and payment-processor records and the
  general ledger.
- Balanced entries alone can't detect an omitted transaction, or a balanced
  posting to the wrong customer.
- *Source:* Stripe runs explicit completeness and cross-system checks (as
  above).
- *Test:* for a set of external records, every record matches exactly one
  ledger event and vice versa. Unmatched items are reported, not dropped.

**LR23. Replaying or rebuilding never repeats external actions. (PRODUCTION)**
Recomputing history, by a full rebuild or a retroactive replay, must not resend
payments, notifications or any other external action.
- *Sources:*
  - Fowler: during replay, it is "usually sufficient for the gateways to be able
    to be disabled" ([Event Sourcing](https://martinfowler.com/eaaDev/EventSourcing.html));
  - [Retroactive Event](https://martinfowler.com/eaaDev/RetroactiveEvent.html)
    sends compensating messages only for the difference.
- *Test:* during a rebuild or retroactive replay, the external gateways record
  zero sends, apart from any deliberate compensating messages.

## How these become checks

| Rule | Fixed-amount spec (step 1) | Interest spec (step 2) | Running system |
|---|---|---|---|
| LR1, LR2, LR15 | yes (one currency) | yes | yes |
| LR3, LR4, LR6, LR7 | yes | yes | yes |
| LR5 | the balancing rule in the model; the counterpart by LR22 | as step 1 | LR22 |
| LR8, LR9, LR10, LR11 | yes: the core claims, with same-day order and eligibility | yes, with accrued interest and residuals | conformance |
| LR12 | allocation order without interest | yes | conformance |
| LR13, LR14 | not applicable | yes | conformance |
| LR16, LR17 | yes, as model properties and conformance | yes | yes |
| LR18 to LR23 | outside the model | outside the model | design review plus tests of the running system |

The paper's own requirements map onto these:
- R1 (correctness) is LR8, now over all forward-looking state;
- R2 (audit immutability) is LR3, by posting sequence;
- R3 (traceability) is LR6, which now also needs links to the corrected
  originals;
- R4 (composability) is LR8 over sequences with several late events.

## Changes from v1 (owner's review, 2026-11-18)

- **LR1:** an exact fixed-point decimal is allowed as an alternative; currency,
  scale, limits and overflow are stated; the test is per currency, not "a
  multiple of 0.01".
- **LR2:** posting frequency and an explicit residual policy were added, and
  splits allocate remainders deterministically.
- **LR3, LR4:** the order is posting sequence; "reported then" is separated from
  "calculated now"; opening balances are auditable.
- **LR5:** a currency or valuation basis is stated; counterpart reconciliation
  is tested (LR22), no longer left to design review.
- **LR6, LR7:** corrections link to the originals; reversals are tested for
  exact offsetting amounts and accounts.
- **LR8 to LR10:** limited to eligible events in open periods, with
  closed-period treatment, a same-day ordering rule and dependencies; the
  comparison covers all forward-looking state.
- **LR14:** missing initial rates, duplicate starts, superseded versions and
  change-day timing are defined; storage order never resolves conflicts.
- **LR15:** the test is payment = allocations + unapplied; refunds and returns
  are lifecycle events.
- **LR16:** collision is defined on the complete scoped key; business-event
  deduplication is durable beyond any API cache.
- **LR17:** "same inputs" covers policies, rates, calendars, rounding and the
  evaluation date; accrual uses an explicit cut-off.
- **LR18:** now an explicit production requirement covering atomic commits,
  durable acknowledgements, conflicts and retries.
- **New:** LR19 (atomic posting and crash recovery), LR20 (payment lifecycle),
  LR21 (posting authority and account validity), LR22 (external
  reconciliation), LR23 (replay isolation).
