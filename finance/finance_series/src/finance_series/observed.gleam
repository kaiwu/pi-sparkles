import finance_core/observation.{type Observation}
import finance_series/series.{type Series, type SeriesError}
import gleam/list

/// Build a timeline from complete observation envelopes. Present points retain
/// every provenance field; explicit missing quality becomes a missing datum.
pub fn from_observations(
  observations: List(Observation(value)),
) -> Result(Series(Observation(value)), SeriesError) {
  observations
  |> list.map(fn(observed) {
    let datum = case observed.quality {
      observation.Missing(reason) -> series.Missing(reason)
      _ -> series.Present(observed)
    }
    series.Point(observed.as_of, datum)
  })
  |> series.new
}

pub fn values(observations: Series(Observation(value))) -> Series(value) {
  series.map(observations, fn(observed) { observed.value })
}
