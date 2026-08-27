# Part 5 — Idempotency

## Objective

Part 4 demonstrated that an atomic conditional update can preserve the
prescription fulfillment invariant by combining the critical business
condition and state mutation into one database operation.

Part 5 addresses a different failure mode:

> What happens if the same logical request is delivered more than once?

This can happen when:

    a client retries after a timeout
    a response is lost
    a network connection drops
    an upstream system retries automatically
    the same message is delivered more than once

Without idempotency, the same business operation could be processed
multiple times.

The goal of Part 5 is:

> Repeated delivery of the same logical fulfillment request must produce
> only one committed fulfillment.

## Idempotency Key

Each fulfillment request now includes an HTTP header:

    Idempotency-Key: fill-request-abc123

The key identifies the logical business operation.

Repeated requests using the same key represent retries or duplicate
delivery of the same operation.

The key is persisted with the fulfillment record.

Conceptually:

    Fulfillment
      prescription_id = 1
      status = completed
      idempotency_key = fill-request-abc123

## Schema Change

The fulfillments table now contains:

    idempotency_key

The migration adds the column and a unique database index:

    add_column :fulfillments,
               :idempotency_key,
               :string,
               null: false

    add_index :fulfillments,
              :idempotency_key,
              unique: true

The unique index is critical.

Application logic may check whether a key already exists, but two
duplicate requests can perform that check concurrently:

    Request A checks key ABC
    → not found

    Request B checks key ABC
    → not found

Both requests could then attempt to insert the same key.

The PostgreSQL unique index provides the authoritative guarantee that
only one fulfillment can be persisted for a given idempotency key.

## Request Flow

The request flow is:

    receive request
        ↓
    read Idempotency-Key
        ↓
    key missing?
        ↓
    reject request

Otherwise:

    look for existing fulfillment
        ↓
    existing key?
      ↓        ↓
    yes       no
      ↓        ↓
    return    execute business transaction
    existing       ↓
    result     atomic conditional update
                    ↓
               create fulfillment
               with idempotency key
                    ↓
                 COMMIT

## Replay Behavior

If a fulfillment already exists for the supplied idempotency key, the
application returns the existing result rather than executing the
business operation again.

Example:

    {
      "prescription_id": 1,
      "status": "fulfilled",
      "remaining_fills": 0,
      "idempotency_key": "fill-request-abc123",
      "replayed": true
    }

The `replayed` flag indicates that the request did not create a new
fulfillment.

## First Execution

The first successful request for a new key returns:

    {
      "prescription_id": 1,
      "status": "fulfilled",
      "remaining_fills": 0,
      "idempotency_key": "fill-request-abc123",
      "replayed": false
    }

This request performs the real business operation.

## Concurrent Duplicate Requests

The test began with:

    remaining_fills = 1
    fulfillments = 0

Ten concurrent requests were submitted with the same key:

    Idempotency-Key: fill-request-abc123

Observed behavior:

    one request:
    replayed = false

    duplicate requests:
    replayed = true

The final database state was:

    remaining_fills = 0
    fulfillments = 1
    idempotency_keys = ["fill-request-abc123"]

Therefore:

> Ten deliveries of the same logical request produced one committed
> fulfillment.

## Database-Level Protection

The application lookup provides the normal replay path:

    Fulfillment.find_by(idempotency_key: key)

But the database unique constraint is the final protection against a
concurrent duplicate race.

If two requests attempt to persist the same key concurrently,
PostgreSQL allows only one insert.

The losing request encounters a uniqueness conflict and can then load
the already-created fulfillment and return it as a replay.

Conceptually:

    Request A                  Request B
        ↓                          ↓
    key not found              key not found
        ↓                          ↓
    insert ABC                 insert ABC
        ↓                          ↓
    succeeds                   UNIQUE conflict
        ↓                          ↓
    COMMIT                     load existing ABC
                                   ↓
                               return replay

## Transaction Boundary

The atomic conditional update and fulfillment creation remain inside the
same database transaction.

Conceptually:

    BEGIN
        ↓
    guarded decrement
        ↓
    create fulfillment
    with idempotency key
        ↓
    COMMIT

If fulfillment creation fails, the prescription decrement is rolled
back.

This prevents partial states such as:

    remaining_fills = 0
    fulfillments = 0

## Idempotency vs. Concurrency Control

Idempotency solves a different problem from the concurrency mechanisms
demonstrated in Parts 2 through 4.

Concurrency control asks:

> What if different operations compete for the same authoritative state?

Idempotency asks:

> What if the same logical operation is delivered more than once?

These protections complement each other.

Part 4 protects:

    one remaining fill
        ↓
    multiple competing fulfillment attempts
        ↓
    at most one successful state transition

Part 5 protects:

    one logical fulfillment request
        ↓
    multiple deliveries or retries
        ↓
    one committed business outcome

## Why Both Matter

A production system can experience both problems at the same time.

For example:

    multiple users may attempt competing operations

while:

    clients, queues, or services may retry requests

Correctness therefore requires protection against both shared-state
contention and duplicate delivery.

## Key Principle

> Idempotency ensures that repeated delivery of the same logical
> operation produces the same business outcome rather than performing
> the operation multiple times.

The application provides a replay path.

The PostgreSQL unique constraint provides the authoritative duplicate
protection.

Together with the atomic state transition from Part 4, this produces a
more robust fulfillment workflow under concurrency, retries, and
duplicate delivery.
