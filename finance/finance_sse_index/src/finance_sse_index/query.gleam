pub opaque type Query {
  Query
}

pub type QueryError {
  UnsupportedIndexIdentity
}

pub fn constituents(venue: String, code: String) -> Result(Query, QueryError) {
  case venue, code {
    "sse", "000688" -> Ok(Query)
    _, _ -> Error(UnsupportedIndexIdentity)
  }
}

pub fn venue(_query: Query) -> String {
  "sse"
}

pub fn mic(_query: Query) -> String {
  "XSHG"
}

pub fn code(_query: Query) -> String {
  "000688"
}

pub fn name(_query: Query) -> String {
  "科创50"
}

pub fn expected_members(_query: Query) -> Int {
  50
}
