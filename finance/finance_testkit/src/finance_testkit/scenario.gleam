import gleam/list

pub type Trace(model, effect) {
  Trace(final: model, states: List(model), effects: List(effect))
}

pub fn run(
  initial: model,
  events: List(event),
  with update: fn(model, event) -> #(model, List(effect)),
) -> Trace(model, effect) {
  let #(final, reversed_states, effects) =
    list.fold(events, #(initial, [initial], []), fn(accumulator, event) {
      let #(current, states, effects) = accumulator
      let #(next, emitted) = update(current, event)
      #(next, [next, ..states], list.append(effects, emitted))
    })
  Trace(final, list.reverse(reversed_states), effects)
}
