# Part 3 — Optimistic Locking

## Objective

Part 2 demonstrated that pessimistic row locking can preserve the
prescription fulfillment invariant by forcing transactions competing
for the same prescription row to wait.

Starting with:

    remaining_fills = 1
    fulfillments = 0

Ten concurrent requests resulted in:

    remaining_fills = 0
    fulfillments = 1

The result was correct, but competing transactions were serialized
around the locked row.

Part 3 demonstrates optimistic locking as an alternative concurrency
strategy.

Instead of acquiring a row lock before performing the business logic,
transactions are allowed to proceed concurrently.

A version token is used to detect whether the authoritative state
changed between the original read and the attempted write.

## Schema Change

A `lock_version` column was added to the `prescriptions` table:

    add_column :prescriptions,
               :lock_version,
               :integer,
               null: false,
               default: 0

Rails Active Record recognizes `lock_version` as its standard
optimistic-locking column.

Each successful update increments the value.

For example:

    lock_version = 0
          ↓
    successful update
          ↓
    lock_version = 1

## Optimistic Locking Model

Suppose two concurrent transactions read:

    remaining_fills = 1
    lock_version = 0

Both transactions are initially allowed to proceed.

Conceptually:

    Transaction A                     Transaction B

    READ fills=1, version=0           READ fills=1, version=0
            ↓                                 ↓
    business rule valid              business rule valid
            ↓                                 ↓
    attempt update                    attempt update

Transaction A reaches the version-checked write first.

Conceptually, its update is equivalent to:

    UPDATE prescriptions
    SET remaining_fills = 0,
        lock_version = 1
    WHERE id = 1
      AND lock_version = 0;

The update succeeds because version `0` is still current.

The authoritative state becomes:

    remaining_fills = 0
    lock_version = 1

Transaction B then attempts a write based on version `0`.

The version check no longer matches.

Rails detects the stale write and raises:

    ActiveRecord::StaleObjectError

The transaction is rolled back.

## Implementation

The fulfillment operation executes inside a normal database transaction:

    Prescription.transaction do
      Fulfillment.create!(
        prescription: prescription,
        status: "completed"
      )

      prescription.update!(
        remaining_fills: prescription.remaining_fills - 1
      )
    end

There is no pessimistic `with_lock` around the business operation.

Instead, Rails uses the persisted `lock_version` value when updating the
prescription.

A stale write is handled explicitly:

    rescue ActiveRecord::StaleObjectError
      prescription.reload

      return render json: {
        error: "Prescription changed during fulfillment",
        remaining_fills: prescription.remaining_fills
      }, status: :conflict
    end

Because fulfillment creation and prescription modification occur inside
the same transaction, a stale prescription update causes the entire
transaction to roll back.

A losing transaction therefore cannot leave behind an additional
fulfillment record.

## Concurrent Test

The test began with:

    remaining_fills = 1
    lock_version = 0
    fulfillments = 0

Ten concurrent fulfillment requests were submitted against the same
prescription.

One request successfully fulfilled the prescription:

    {
      "prescription_id": 1,
      "status": "fulfilled",
      "remaining_fills": 0,
      "lock_version": 1
    }

Some competing requests had already read version `0` before the winning
transaction committed.

Those requests encountered stale-write conflicts:

    {
      "error": "Prescription changed during fulfillment",
      "remaining_fills": 0
    }

Later requests observed the already-committed state and were rejected
before attempting a write:

    {
      "error": "No fills remaining"
    }

The final database state was:

    remaining_fills = 0
    lock_version = 1
    fulfillments = 1

The business invariant remained intact:

> One authorized remaining fill can produce at most one successful
> fulfillment record.

## Why It Works

Optimistic locking does not prevent concurrent transactions from
reading the same state.

Instead, it verifies at write time that the state has not changed since
the transaction originally read it.

The principle is:

    READ version N
          ↓
    perform business logic
          ↓
    WRITE only if version is still N
          ↓
    successful write → version N + 1
    stale version     → reject and rollback

The version token therefore detects stale application state.

## Retry Behavior

A stale transaction is not necessarily permanently abandoned.

The application may choose to retry it.

However, a retry must first reload the current authoritative state and
re-evaluate the business rules.

For example, if the original state was:

    remaining_fills = 1

and another transaction consumed that fill, a retry sees:

    remaining_fills = 0

The business rule therefore rejects the operation.

If several fills still remained, the operation might still be valid
after reloading and could potentially be retried against the newer
version.

Concurrency control detects stale state.

The business invariant determines whether the operation may proceed.

## Optimistic Locking vs. MVCC

Optimistic locking and PostgreSQL MVCC are related concurrency concepts,
but they are not the same mechanism.

### PostgreSQL MVCC

Multi-Version Concurrency Control manages which physical row versions
are visible to concurrent transactions.

Its primary concern is transaction visibility.

Conceptually:

    MVCC
    → Which version of this row may this transaction see?

### Optimistic Locking

Rails optimistic locking uses an application-level version token stored
in PostgreSQL.

Its primary concern is stale-write detection.

Conceptually:

    Optimistic locking
    → Has this row changed since I originally read it?

The `lock_version` counter is therefore not PostgreSQL's internal MVCC
version number.

PostgreSQL provides the transactional database underneath while Active
Record uses the persisted `lock_version` value to detect stale writes.

## Trade-offs

Optimistic locking avoids acquiring an explicit row lock before the
business operation.

This can improve concurrency when conflicts are uncommon.

### Less Blocking

Transactions do not wait up front merely because another transaction is
working with the same row.

### Efficient When Conflicts Are Rare

If most operations affect different records, the majority of writes can
complete without additional coordination or waiting.

### Failed Work Under Contention

When many transactions compete for the same state, several may perform
work that ultimately becomes stale.

Those transactions must fail or retry.

### Retry Cost

Retries consume additional application and database resources.

A heavily contended row can therefore generate repeated stale conflicts
rather than a waiting queue.

### Business Logic Must Be Re-Evaluated

A retry cannot blindly repeat the original write.

The current authoritative state must be reloaded and the business
invariant evaluated again.

## Pessimistic vs. Optimistic Locking

Pessimistic locking coordinates conflicts before the operation:

    LOCK
      ↓
    CHECK
      ↓
    WRITE
      ↓
    COMMIT

Competing transactions wait.

Optimistic locking detects conflicts at write time:

    READ VERSION
         ↓
    CHECK
         ↓
    ATTEMPT WRITE
         ↓
    current version?
      ↓          ↓
    yes         no
    COMMIT      STALE CONFLICT
                ROLLBACK

The trade-off can be summarized as:

    Pessimistic locking
    → pay the cost of waiting when contention occurs

    Optimistic locking
    → pay the cost of failed writes and retries when contention occurs

Neither strategy is universally correct for every workload.

The appropriate mechanism depends on conflict frequency, transaction
duration, throughput requirements, retry cost, and the business
criticality of the protected state.

## Key Principle

> Optimistic locking allows concurrent operations to proceed, but only
> the first successful write against the current version commits;
> competing writes based on stale state are rejected and rolled back.

Part 3 demonstrates optimistic locking as an alternative to the
pessimistic strategy from Part 2.

The next stage will examine atomic conditional updates as another way to
protect the same business invariant.
