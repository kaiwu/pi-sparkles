import finance_core/identifier.{type InstrumentId, type Mic, type Symbol}
import finance_track.{type Track}

/// A track-scoped listing identity. A symbol alone is never a listing key.
pub opaque type Key {
  Key(track: Track, instrument_id: InstrumentId, symbol: Symbol, mic: Mic)
}

pub fn new(
  track track: Track,
  instrument_id instrument_id: InstrumentId,
  symbol symbol: Symbol,
  mic mic: Mic,
) -> Key {
  Key(track, instrument_id, symbol, mic)
}

pub fn track(value: Key) -> Track {
  value.track
}

pub fn instrument_id(value: Key) -> InstrumentId {
  value.instrument_id
}

pub fn symbol(value: Key) -> Symbol {
  value.symbol
}

pub fn mic(value: Key) -> Mic {
  value.mic
}
