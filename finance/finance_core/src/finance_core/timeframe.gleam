pub type Timeframe {
  Tick
  Minute(count: Int)
  Hour(count: Int)
  Day(count: Int)
  Week(count: Int)
  Month(count: Int)
}

pub type TimeframeError {
  NonPositiveCount
}

pub fn minute(count: Int) -> Result(Timeframe, TimeframeError) {
  positive(Minute, count)
}

pub fn hour(count: Int) -> Result(Timeframe, TimeframeError) {
  positive(Hour, count)
}

pub fn day(count: Int) -> Result(Timeframe, TimeframeError) {
  positive(Day, count)
}

pub fn week(count: Int) -> Result(Timeframe, TimeframeError) {
  positive(Week, count)
}

pub fn month(count: Int) -> Result(Timeframe, TimeframeError) {
  positive(Month, count)
}

fn positive(
  constructor: fn(Int) -> Timeframe,
  count: Int,
) -> Result(Timeframe, TimeframeError) {
  case count > 0 {
    True -> Ok(constructor(count))
    False -> Error(NonPositiveCount)
  }
}
