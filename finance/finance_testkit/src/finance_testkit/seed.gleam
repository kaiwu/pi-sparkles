const modulus = 2_147_483_647

const multiplier = 48_271

pub opaque type Seed {
  Seed(value: Int)
}

pub type SeedError {
  InvalidSeed
  InvalidRange
}

pub fn new(value: Int) -> Result(Seed, SeedError) {
  case value > 0 && value < modulus {
    True -> Ok(Seed(value))
    False -> Error(InvalidSeed)
  }
}

pub fn value(seed: Seed) -> Int {
  let Seed(value) = seed
  value
}

pub fn next(seed: Seed) -> #(Seed, Int) {
  let Seed(value) = seed
  let next_value = { value * multiplier } % modulus
  #(Seed(next_value), next_value)
}

pub fn between(
  seed: Seed,
  minimum: Int,
  maximum: Int,
) -> Result(#(Seed, Int), SeedError) {
  case minimum <= maximum {
    False -> Error(InvalidRange)
    True -> {
      let #(next_seed, generated) = next(seed)
      let width = maximum - minimum + 1
      Ok(#(next_seed, minimum + { generated % width }))
    }
  }
}
