# Transaction Workflow — Version 0.1

## Request

`POST /prescriptions/:id/fulfill`

## Preconditions

A fulfillment request may proceed only if:

- the prescription exists
- the prescription is active
- `remaining_fills > 0`

## Successful Transaction

A successful fulfillment must:

1. Load the prescription.
2. Verify the prescription is active.
3. Verify at least one fill remains.
4. Create one fulfillment record.
5. Decrement `remaining_fills` by one.
6. Commit the transaction.
7. Return success.

## Failed Transaction

If any required condition fails:

- no fulfillment record is created
- `remaining_fills` is unchanged
- the transaction is rolled back
- the request returns failure

## Core Invariant

One authorized remaining fill can produce at most one successful fulfillment.

## Version 0.1 Naive Strategy

The first implementation will deliberately use a simple:

`READ → CHECK → WRITE`

workflow so that concurrent requests can expose a race condition.

## Expected Concurrency Failure

If multiple requests read the same prescription before another request commits its change, more than one request may conclude that a fill is available.

The first experiment will attempt to reproduce that invalid outcome.

## Next Step

Translate this workflow into the minimal `Prescription` and `Fulfillment` Rails models.