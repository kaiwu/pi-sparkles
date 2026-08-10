import gleam/dynamic/decode as decoder

pub type ManifestInput {
  ManifestInput(manifest_json: String, manifest_hash: String)
}

pub type PageInput {
  PageInput(partition: String, offset: Int, limit: Int)
}

pub type Input {
  Input(
    track: String,
    effective_date: String,
    knowledge_cutoff_unix_ms: Int,
    universe: ManifestInput,
    page: PageInput,
  )
}

pub fn input() -> decoder.Decoder(Input) {
  use track <- decoder.field("track", decoder.string)
  use effective_date <- decoder.field("effectiveDate", decoder.string)
  use knowledge_cutoff <- decoder.field(
    "knowledgeCutoffUnixMilliseconds",
    decoder.int,
  )
  use universe <- decoder.field("universe", manifest_decoder())
  use page <- decoder.field("page", page_decoder())
  decoder.success(Input(track, effective_date, knowledge_cutoff, universe, page))
}

fn manifest_decoder() -> decoder.Decoder(ManifestInput) {
  use manifest_json <- decoder.field("manifestJson", decoder.string)
  use manifest_hash <- decoder.field("manifestHash", decoder.string)
  decoder.success(ManifestInput(manifest_json, manifest_hash))
}

fn page_decoder() -> decoder.Decoder(PageInput) {
  use partition <- decoder.field("partition", decoder.string)
  use offset <- decoder.field("offset", decoder.int)
  use limit <- decoder.field("limit", decoder.int)
  decoder.success(PageInput(partition, offset, limit))
}
