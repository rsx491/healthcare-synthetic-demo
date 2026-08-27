# Part 5 — Demo Commands

## Verify Schema

Confirm Rails sees the idempotency key:

    docker compose exec web bin/rails runner \
    'puts "column_exists=#{Fulfillment.column_names.include?("idempotency_key")}"; puts Fulfillment.connection.indexes(:fulfillments).map { |i| [i.name, i.unique, i.columns] }.inspect'

Expected:

    column_exists=true

and a unique index:

    index_fulfillments_on_idempotency_key
    unique=true

## Reset Initial State

    docker compose exec web bin/rails runner \
    'Fulfillment.delete_all; p = Prescription.find(1); p.update_columns(remaining_fills: 1, status: "active", lock_version: 0); puts "fills=#{p.reload.remaining_fills} fulfillments=#{Fulfillment.count}"'

Expected:

    fills=1
    fulfillments=0

## Run Concurrent Duplicate Requests

Submit ten concurrent requests using the same logical idempotency key:

    for i in {1..10}; do
      curl -s -X POST \
        -H "Idempotency-Key: fill-request-abc123" \
        http://localhost:3000/prescriptions/1/fulfill &
    done
    wait

Expected behavior:

    one request returns:
    replayed=false

    repeated deliveries return:
    replayed=true

All requests use the same key:

    fill-request-abc123

## Verify Final State

    docker compose exec web bin/rails runner \
    'puts "fills=#{Prescription.find(1).remaining_fills}"; puts "fulfillments=#{Fulfillment.count}"; puts "keys=#{Fulfillment.pluck(:idempotency_key).inspect}"'

Expected:

    fills=0
    fulfillments=1
    keys=["fill-request-abc123"]

## Result

Ten deliveries of the same logical fulfillment request produce one
committed fulfillment.

The first request performs the business operation.

Subsequent duplicate deliveries return the already-existing fulfillment
rather than decrementing another fill or creating another record.

The PostgreSQL unique index on `idempotency_key` provides the final
database-level guarantee against concurrent duplicate insertion.
