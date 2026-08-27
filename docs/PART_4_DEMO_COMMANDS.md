# Part 4 — Demo Commands

## Reset Initial State

docker compose exec web bin/rails runner \
'Fulfillment.delete_all; p = Prescription.find(1); p.update_columns(remaining_fills: 1, status: "active", lock_version: 0); puts "fills=#{p.reload.remaining_fills} lock_version=#{p.lock_version} fulfillments=#{Fulfillment.count}"'

Expected:

fills=1
lock_version=0
fulfillments=0

## Run Concurrent Workload

for i in {1..10}; do
  curl -s -X POST http://localhost:3000/prescriptions/1/fulfill &
done
wait

Expected behavior:

- One request succeeds.
- Nine requests are rejected because the conditional update affects zero rows.

Example success:

{"prescription_id":1,"status":"fulfilled","remaining_fills":0}

Example rejection:

{"error":"Prescription is not active or has no fills remaining","remaining_fills":0}

## Verify Final State

docker compose exec web bin/rails runner \
'puts "fills=#{Prescription.find(1).remaining_fills}"; puts "lock_version=#{Prescription.find(1).lock_version}"; puts "fulfillments=#{Fulfillment.count}"'

Expected:

fills=0
lock_version=0
fulfillments=1

## Result

Part 4 demonstrates that the prescription invariant can be preserved by
combining the business condition and state mutation into one atomic
PostgreSQL update.

The final `lock_version=0` confirms that this example does not rely on
Rails optimistic locking.
