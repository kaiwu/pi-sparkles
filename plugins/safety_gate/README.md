# pi_sparkles_safety_gate

Reference Pi extension written in Gleam. It demonstrates typed event decoding,
an asynchronous UI decision, and fail-safe behavior when no UI is available.

`check.gleam` is the functional core. It classifies a command into the algebraic
`Ordinary` or `RequiresConfirmation(List(Risk))` states and projects typed risks
to an explanation without Pi or UI access. The root effect shell exhaustively
interprets that decision: allow ordinary work, request confirmation when a UI is
available, or fail closed otherwise. Pure tests cover individual and composed
risk classifications; Bun contracts cover only Pi decoding and async UI wiring.

This package is not published to Hex yet.
