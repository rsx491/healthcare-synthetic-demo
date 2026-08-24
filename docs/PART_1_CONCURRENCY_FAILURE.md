# Part 1 — Concurrency Failure

## Objective

Demonstrate that a prescription fulfillment workflow that behaves correctly under sequential requests can violate its business invariant under concurrent requests.

## Business Invariant

> One authorized fill can produce at most one successful fulfillment.

## Initial State

The experiment begins with:

- `remaining_fills = 1`
- `fulfillments = 0`
- prescription status = `active`

## Sequential Baseline

Two sequential requests were submitted against the same prescription.

### First Request

The first request succeeded:

- `remaining_fills`: 1 → 0
- one fulfillment created

### Second Request

The second request was rejected:

`No fills remaining`

Sequential behavior therefore preserved the business invariant.

## Concurrent Experiment

The prescription was reset to:

- `remaining_fills = 1`
- `fulfillments = 0`

Ten concurrent fulfillment requests were then submitted.

A temporary `sleep 0.25` was introduced after the availability check to widen the concurrency window and make the race condition reproducible.

The delay does not create the underlying correctness problem. It makes the unprotected `READ → CHECK → WRITE` race easier to observe during the demonstration.

## Observed Result

After the concurrent workload:

    fills=0
    fulfillments=3

## Expected Result

The valid state was:

    fills=0
    fulfillments=1

## Failure

Three fulfillment records were created from one authorized remaining fill.

The prescription row itself ended at `remaining_fills = 0`, but the associated fulfillment records exposed the integrity violation.

Therefore:

> Expected fulfillments: 1  
> Actual fulfillments: 3  
> Business invariant: VIOLATED

## Cause

Multiple concurrent requests were able to read the same available state before another request completed its state transition.

Each request independently observed:

    remaining_fills > 0

and proceeded based on that observation.

The current transaction protects the writes within each individual request, but it does not protect the earlier decision from concurrent transactions operating on the same prescription.

## Part 1 Conclusion

The naive implementation is correct under the demonstrated sequential workload but is not safe under the demonstrated concurrent workload.

Part 2 will introduce concurrency control and repeat the identical workload to determine whether the invariant is preserved.