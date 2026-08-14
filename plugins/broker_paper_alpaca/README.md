# pi_sparkles_broker_paper_alpaca

Status: **Experimental implementation — owned by T6** · named local simulation plus external Alpaca receipt review

`simulate_alpaca_tape_possible_fill` runs the shared bounded
`transaction_tape_possible_fill_v1` model for an exact US limit instruction and
external Alpaca tape. `review_alpaca_paper_evidence` separately reviews
externally produced paper-account/order/fill lifecycle evidence. The simulation
always retains a compatible non-fill branch and never claims queue position or
an observed broker fill.

Alpaca, its SDK, credentials, adapter, transport, and broker-hosted paper
effects are explicit external dependencies and are not shipped. Focused core
and Pi coverage lives in `finance_execution` and
`test/binding/broker_paper.test.js`.
