# Healthcare Synthetic Demo

Small Rails + PostgreSQL demo for testing concurrency, transactional integrity, and idempotent prescription fulfillment.

## Stack

- Ruby on Rails
- PostgreSQL
- Puma
- Docker
- Docker Compose

## Bootstrap

Build and start the application:

    docker compose up --build -d

Set up the database:

    docker compose exec web bin/rails db:create
    docker compose exec web bin/rails db:migrate

Open the Rails console:

    docker compose exec web bin/rails console

Application URL:

    http://localhost:3000

## Tests

Run the Rails test suite:

    docker compose exec web bin/rails test

Run RuboCop:

    docker compose exec web bundle exec rubocop

## Restart Rails

Useful after migrations or schema changes:

    docker compose restart web

## Stop

Stop the containers:

    docker compose down

Stop the containers and remove the PostgreSQL volume:

    docker compose down -v

## Demo Focus

The project demonstrates:

- naive concurrency failure
- pessimistic locking
- optimistic locking
- atomic conditional updates
- idempotent request handling

Core invariant:

> One authorized fill can produce at most one successful fulfillment.

## Run the Demo

Once the application and database are running, move to the `docs` directory and begin with Part 1:

    cd docs

Start with:

    PART_1_NAIVE_CONCURRENCY.md

Part 1 establishes the baseline concurrency failure. From there, work through the demo parts in order to compare each concurrency-control strategy.

The progression is:

1. Naive concurrency failure
2. Pessimistic row locking
3. Optimistic locking
4. Atomic conditional update
5. Idempotency / duplicate-request protection

Each document contains the explanation and commands needed for that stage of the experiment.