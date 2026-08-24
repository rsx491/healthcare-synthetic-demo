# Part 1 — Demo Commands

## Start Environment

    docker compose up -d
    docker compose ps

## Reset and Verify Initial State

    docker compose exec web bin/rails runner \
    'Fulfillment.delete_all; p = Prescription.find(1); p.update!(remaining_fills: 1, status: "active")'

    docker compose exec web bin/rails runner \
    'puts "fills=#{Prescription.find(1).remaining_fills}"; puts "fulfillments=#{Fulfillment.count}"'

Expected:

    fills=1
    fulfillments=0

## Sequential Request

    curl -s -X POST http://localhost:3000/prescriptions/1/fulfill

Expected successful response:

    {"prescription_id":1,"status":"fulfilled","remaining_fills":0}

Run it again:

    curl -s -X POST http://localhost:3000/prescriptions/1/fulfill

Expected rejection:

    {"error":"No fills remaining"}

## Reset Before Concurrent Test

    docker compose exec web bin/rails runner \
    'Fulfillment.delete_all; p = Prescription.find(1); p.update!(remaining_fills: 1, status: "active")'

Verify the reset:

    docker compose exec web bin/rails runner \
    'puts "fills=#{Prescription.find(1).remaining_fills}"; puts "fulfillments=#{Fulfillment.count}"'

Expected:

    fills=1
    fulfillments=0

## Concurrent Workload

    for i in {1..10}; do
      curl -s -X POST http://localhost:3000/prescriptions/1/fulfill &
    done
    wait

## Inspect Final State

    docker compose exec web bin/rails runner \
    'puts "fills=#{Prescription.find(1).remaining_fills}"; puts "fulfillments=#{Fulfillment.count}"'

Observed during Part 1:

    fills=0
    fulfillments=3

Correct invariant-preserving state:

    fills=0
    fulfillments=1

## Result

Part 1 demonstrates a reproducible concurrency integrity failure.

One authorized fill produced three fulfillment records under concurrent requests.

The business invariant was violated:

> One authorized fill can produce at most one successful fulfillment.