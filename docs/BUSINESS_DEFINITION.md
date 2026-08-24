# Healthcare Synthetic Demo — Version 0.1

**Objective:** Demonstrate whether a simple prescription-fulfillment workflow preserves its core business rule under concurrent requests.

**Invariant:** One authorized fill can produce at most one successful fulfillment.

**Experiment:** Run the naive implementation under concurrent load and observe whether the invariant breaks.

**Measure:** Requests, successful fulfillments, rejected requests, final remaining-fill count, and whether invalid state was created.

**Then:** Apply one concurrency-control solution, rerun the same workload, and compare the result.

**Principle:** Define → Build → Break → Explain → Fix → Prove.
