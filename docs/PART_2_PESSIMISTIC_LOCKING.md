# Part 2 — Pessimistic Row Locking

## Objective

Part 1 demonstrated that a database transaction by itself does not
necessarily protect a business invariant from concurrent requests.

Starting with:

    remaining_fills = 1
    fulfillments = 0

Ten concurrent fulfillment requests resulted in:

    remaining_fills = 0
    fulfillments = 3

Multiple transactions were able to observe the same valid prescription
state and independently decide that fulfillment was allowed.

Part 2 introduces pessimistic row locking to protect the prescription
while that business decision is being made.

## Implementation

The fulfillment workflow now executes inside:

    prescription.with_lock do
      ...
    end

Conceptually, the transaction becomes:

    LOCK prescription row
        ↓
    validate prescription status
        ↓
    validate remaining_fills
        ↓
    create fulfillment
        ↓
    decrement remaining_fills
        ↓
    COMMIT
        ↓
    release lock

The lock therefore protects both the business decision and the
subsequent state change.

## Concurrent Behavior

The same test from Part 1 was repeated:

    remaining_fills = 1
    fulfillments = 0

Ten concurrent requests were submitted against the same prescription.

With pessimistic locking enabled, the result was:

    remaining_fills = 0
    fulfillments = 1

One request acquired the row lock first and successfully consumed the
remaining authorized fill.

Requests competing for the same prescription row waited for that
transaction to complete. After acquiring the lock, they observed the
updated state:

    remaining_fills = 0

and were rejected with:

    No fills remaining

The business invariant was therefore preserved:

> One authorized remaining fill can produce at most one successful
> fulfillment record.

## Why It Works

Pessimistic locking assumes that conflicting operations may occur and
coordinates them before allowing the protected state to be modified.

Requests operating on the same prescription are serialized around that
prescription row.

This does not serialize the entire application or database.

Requests operating on different prescription records can continue to
execute concurrently.

## Trade-offs

The result is correct, but correctness has a cost.

### Blocking

A transaction attempting to acquire a lock already held by another
transaction must wait.

### Increased Latency Under Contention

If many requests compete for the same row, they form a queue behind the
transaction holding the lock.

A frequently accessed row can therefore become a "hot row."

### Reduced Throughput for Contended State

Horizontal application scaling does not eliminate this bottleneck.

Adding additional Rails containers can increase overall application
capacity, but requests competing for the same authoritative database
state must still coordinate access to that state.

### Lock Duration

Locks should be held for as little time as possible.

Slow network calls, external API requests, or unnecessary processing
should generally not occur while holding a database row lock because
they increase the amount of time competing transactions must wait.

### Deadlocks

More complex transactions may acquire multiple locks.

If two transactions acquire those locks in different orders, each can
end up waiting for a lock held by the other. PostgreSQL can detect such
deadlocks and abort one transaction, but applications should still use
consistent locking strategies and handle retries appropriately.

## Design Trade-off

Pessimistic locking prioritizes correctness when contention is possible
by making conflicting transactions wait.

The trade-off is:

    stronger coordination
            ↓
    increased blocking
            ↓
    potentially higher latency under contention

For workloads where conflicts are uncommon, other approaches such as
optimistic locking may preserve correctness while allowing greater
concurrency.

For highly contended state, pessimistic locking can be appropriate
because conflicts are coordinated before competing writes are allowed
to proceed.

## Key Principle

> Preserve concurrency everywhere possible; serialize only operations
> that compete for the same authoritative business state.

Part 2 demonstrates one solution to the concurrency failure from Part 1.
It is not intended to establish pessimistic locking as the correct
solution for every workload.

Subsequent examples can compare this behavior with optimistic locking,
atomic conditional updates, and idempotency controls.
