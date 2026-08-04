# pi_sparkles_hello

Reference Pi extension written in Gleam. It registers a `/hello` command and a
typed `hello` tool.

The root module is the Pi effect shell: it decodes tool input and performs UI or
tool-result effects. `greeting.gleam` is a reusable pure function whose output
depends only on its argument. This small split is the minimum form of the
repository's `FUNCTIONAL_DESIGN.md` architecture.

This package exists to prove the Gleam-to-Pi binding and build pipeline. It is
not published to Hex yet.
