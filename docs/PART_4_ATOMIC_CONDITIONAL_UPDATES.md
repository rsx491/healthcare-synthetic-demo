# Part 4 — Atomic Conditional Updates

## Objective

Part 3 demonstrated optimistic locking as a way to preserve the
prescription fulfillment invariant without acquiring a pessimistic row
lock before the business operation.

Starting with:

    remaining_fills = 1
    lock_version = 0
    fulfillments = 0

Ten concurrent requests resulted in:

    remaining_fills = 0
    lock_version = 1
    fulfillments = 1

Part 4 demonstrates a different concurrency strategy.

Instead of:

    READ
      ↓
    CHECK
      ↓
    WRITE

the critical business condition and state mutation are combined into
one atomic PostgreSQL update.

## Implementation

The critical operation is:

    updated_rows = Prescription
      .where(
        id: prescription.id,
        status: "active"
      )
      .where("remaining_fills > 0")
      .update_all("remaining_fills = remaining_fills - 1")

Conceptually, Rails translates this into SQL similar to:

    UPDATE prescriptions
    SET remaining_fills = remaining_fills - 1
    WHERE id = 1
      AND status = 'active'
      AND remaining_fills > 0;

The `.where(...)` clauses define when the state transition is valid.

The `.update_all(...)` call performs the actual write.

PostgreSQL returns the number of rows affected.

    updated_rows = 1
    → the transition succeeded

    updated_rows = 0
    → the transition was no longer valid

## Transaction Boundary

The conditional decrement and fulfillment creation execute inside the
same transaction:

    Prescription.transaction do
      updated_rows = Prescription
        .where(
          id: prescription.id,
          status: "active"
        )
        .where("remaining_fills > 0")
        .update_all("remaining_fills = remaining_fills - 1")

      if updated_rows == 1
        Fulfillment.create!(
          prescription: prescription,
          status: "completed"
        )
      end
    end

This prevents a partial state such as:

    remaining_fills = 0
    fulfillments = 0

If fulfillment creation fails after the decrement, the transaction
rolls back the decrement as well.

## Concurrent Test

The test began with:

    remaining_fills = 1
    lock_version = 0
    fulfillments = 0

Ten concurrent fulfillment requests were submitted against the same
prescription.

One request successfully satisfied the guarded database condition:

    status = 'active'
    remaining_fills > 0

That request decremented the prescription and created the fulfillment.

The other requests reached the same atomic update after the remaining
fill had already been consumed.

For those requests:

    remaining_fills > 0

was no longer true.

PostgreSQL therefore updated zero rows and the application rejected the
requests.

The final state was:

    remaining_fills = 0
    lock_version = 0
    fulfillments = 1

The business invariant remained intact:

> One authorized remaining fill can produce at most one successful
> fulfillment record.

## Why lock_version Remained Zero

Part 4 does not rely on Rails optimistic locking.

The final state remained:

    lock_version = 0

because `update_all` performs the guarded database update directly and
does not use Active Record's `lock_version` stale-write mechanism.

That provides a useful confirmation that the correctness guarantee in
Part 4 came from the atomic conditional update itself.

## Why It Works

The authoritative and most important part of the transaction is the
critical state transition:

> Is this prescription still active and does it still have an
> authorized remaining fill at the exact moment the state is changed?

In Parts 1 through 3, the application first loaded state and then
performed some form of concurrency coordination around the later write.

Part 4 instead asks PostgreSQL to evaluate the business condition and
perform the mutation as one atomic operation.

Conceptually:

    CHECK + WRITE
        ↓
    one database statement

rather than:

    READ
      ↓
    CHECK
      ↓
    application processing
      ↓
    WRITE

This removes the application-level race window between evaluating the
business condition and performing the state change.

## Application Layer vs. Data Layer

Part 4 does not move all business logic into PostgreSQL.

Rails still owns:

    request handling
    orchestration
    fulfillment creation
    error responses
    surrounding workflow

PostgreSQL owns the critical state-transition decision:

    Is the row still eligible to be changed right now?

The key principle is:

> Keep orchestration in the application layer, but push the critical
> state transition into a single atomic database operation when
> correctness depends on current authoritative state.

The primary benefit is concurrency correctness.

Reduced application-side coordination overhead is secondary.

## Comparison With Pessimistic Locking

Pessimistic locking:

    LOCK
      ↓
    CHECK
      ↓
    WRITE
      ↓
    COMMIT

Competing transactions wait for access to the protected row.

Atomic conditional update:

    UPDATE ... WHERE condition
            ↓
    condition true?
      ↓            ↓
    yes           no
    write         update zero rows
    succeeds      reject

There is no explicit application-level pessimistic row lock around the
business decision.

## Comparison With Optimistic Locking

Optimistic locking:

    READ version N
        ↓
    perform logic
        ↓
    WRITE only if version is still N
        ↓
    stale version → rollback

Atomic conditional update:

    evaluate current business condition
            +
    perform state mutation
            ↓
      same database statement

Optimistic locking detects that previously read state became stale.

Atomic conditional updates avoid depending on previously read state for
the critical mutation.

## Trade-offs

Atomic conditional updates are especially effective when the critical
state transition can be represented simply in SQL.

### Efficient State Transition

The database performs the condition check and mutation in one
operation.

### Reduced Race Window

There is no separate application-level interval between validating the
critical condition and changing the row.

### Less Application Coordination

No explicit pessimistic lock or application-level optimistic version
comparison is required for this state transition.

### Business Logic Complexity

The approach becomes less attractive when the business transition
requires complex application logic that cannot be expressed clearly or
safely as a guarded database operation.

### Maintainability

Critical SQL conditions must remain understandable and closely aligned
with the documented business invariant.

Moving too much domain logic into SQL can make an application difficult
to maintain.

The goal is not to move all business rules into the database.

The goal is to place the smallest authoritative state transition at the
layer best able to guarantee its correctness.

## Key Principle

> When a critical state transition can be expressed as a single guarded
> database mutation, combining the condition and write atomically can
> eliminate the application-level race window.

Part 4 demonstrates that the same prescription invariant can be
preserved without relying on pessimistic row locking or optimistic
`lock_version` checks.

The next stage will add idempotency protection so repeated delivery of
the same logical request cannot create duplicate business outcomes.
