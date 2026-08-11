import finance_local_import
import finance_transcript
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/int
import gleam/javascript/promise.{type Promise}
import gleam/json.{type Json}
import gleam/list
import pi
import pi/raw
import pi/schema
import pi/tool

pub type SearchInput {
  SearchInput(
    path: String,
    expected_sha256: String,
    maximum_bytes: Int,
    query: String,
    case_sensitive: Bool,
    offset: Int,
    limit: Int,
  )
}

pub type ExcerptInput {
  ExcerptInput(
    path: String,
    expected_sha256: String,
    maximum_bytes: Int,
    segment_id: String,
    context_segments: Int,
  )
}

pub type AlignInput {
  AlignInput(
    left_path: String,
    left_sha256: String,
    right_path: String,
    right_sha256: String,
    maximum_bytes_each: Int,
    query: String,
    case_sensitive: Bool,
    maximum_matches_per_side: Int,
  )
}

pub fn extension(api: pi.ExtensionApi) -> Promise(Nil) {
  tool.register(
    api,
    "transcript_search",
    "Search exact licensed transcript text",
    "Search a bounded content-bound transcript projection without rewriting source text; returns speaker identity/state, exact source offsets, source rights, corrections, omissions, and receipt hashes",
    "Supply transcript text only when your rights permit this use; interpret all passages yourself",
    tool.parameters(search_schema(), search_decoder()),
    tool.Parallel,
    fn(_id, input, signal, _updates, _ctx) {
      run_one(
        input.path,
        input.expected_sha256,
        input.maximum_bytes,
        raw.dynamic(signal),
        fn(value) {
          finance_transcript.search(
            value,
            input.query,
            input.case_sensitive,
            input.offset,
            input.limit,
          )
        },
      )
    },
  )
  tool.register(
    api,
    "transcript_excerpt",
    "Read bounded speaker-aware excerpt",
    "Return one exact transcript segment with at most five neighboring segments on each side, preserving source text, speaker state, offsets, rights, corrections, omissions, and hashes",
    "Choose the exact segment and context bound; the plugin does not summarize or infer speaker intent",
    tool.parameters(excerpt_schema(), excerpt_decoder()),
    tool.Parallel,
    fn(_id, input, signal, _updates, _ctx) {
      run_one(
        input.path,
        input.expected_sha256,
        input.maximum_bytes,
        raw.dynamic(signal),
        fn(value) {
          finance_transcript.excerpt(
            value,
            input.segment_id,
            input.context_segments,
          )
        },
      )
    },
  )
  tool.register(
    api,
    "transcript_align",
    "Align exact topic passages",
    "Search the same exact caller-selected query in two bounded content-bound transcript projections and return independently attributed speaker passages; this is textual alignment, not semantic equivalence",
    "Select both exact transcript versions and the exact query; interpret changes and importance yourself",
    tool.parameters(align_schema(), align_decoder()),
    tool.Parallel,
    fn(_id, input, signal, _updates, _ctx) {
      run_align(input, raw.dynamic(signal))
    },
  )
  promise.resolve(Nil)
}

fn run_one(
  path: String,
  expected: String,
  maximum: Int,
  signal: Dynamic,
  operation: fn(finance_transcript.Transcript) ->
    Result(Json, finance_transcript.TranscriptError),
) -> Promise(tool.ToolResult) {
  use outcome <- promise.await(finance_local_import.read(path, maximum, signal))
  case outcome {
    finance_local_import.Loaded(text, _) ->
      case finance_transcript.load(expected, text) {
        Error(error) -> tool.reject(finance_transcript.error_message(error))
        Ok(value) ->
          case operation(value) {
            Error(error) -> tool.reject(finance_transcript.error_message(error))
            Ok(details) ->
              tool.text_result(finance_transcript.summary(value), details)
              |> promise.resolve
          }
      }
    other -> tool.reject(import_error(other))
  }
}

fn run_align(input: AlignInput, signal: Dynamic) -> Promise(tool.ToolResult) {
  use left_outcome <- promise.await(finance_local_import.read(
    input.left_path,
    input.maximum_bytes_each,
    signal,
  ))
  case left_outcome {
    finance_local_import.Loaded(left_text, _) -> {
      use right_outcome <- promise.await(finance_local_import.read(
        input.right_path,
        input.maximum_bytes_each,
        signal,
      ))
      case right_outcome {
        finance_local_import.Loaded(right_text, _) ->
          case finance_transcript.load(input.left_sha256, left_text) {
            Error(error) -> tool.reject(finance_transcript.error_message(error))
            Ok(left) ->
              case finance_transcript.load(input.right_sha256, right_text) {
                Error(error) ->
                  tool.reject(finance_transcript.error_message(error))
                Ok(right) ->
                  case
                    finance_transcript.align(
                      left,
                      right,
                      input.query,
                      input.case_sensitive,
                      input.maximum_matches_per_side,
                    )
                  {
                    Error(error) ->
                      tool.reject(finance_transcript.error_message(error))
                    Ok(details) ->
                      tool.text_result(
                        "Exact transcript passage alignment; interpretation remains with the LLM",
                        details,
                      )
                      |> promise.resolve
                  }
              }
          }
        other -> tool.reject("Right " <> import_error(other))
      }
    }
    other -> tool.reject("Left " <> import_error(other))
  }
}

fn import_error(value: finance_local_import.Outcome) -> String {
  case value {
    finance_local_import.Truncated(_, total) ->
      "transcript import exceeds maximumBytes; total bytes: "
      <> int.to_string(total)
    finance_local_import.Cancelled -> "transcript import was cancelled"
    finance_local_import.Missing -> "transcript import file was not found"
    finance_local_import.InvalidUtf8 ->
      "transcript import requires strict UTF-8"
    finance_local_import.Failure(code) ->
      "transcript import failed safely: " <> code
    finance_local_import.InvalidResult ->
      "transcript import effect returned an invalid result"
    finance_local_import.Loaded(_, _) -> "unreachable"
  }
}

fn common_fields() -> List(schema.Property) {
  [
    schema.Required("path", bounded_string(1, 4096)),
    schema.Required("expectedSha256", bounded_string(64, 64)),
    schema.Required(
      "maximumBytes",
      schema.integer() |> schema.with_number_range(1.0, 5_000_000.0),
    ),
  ]
}

fn search_schema() -> schema.Schema {
  schema.object(
    list.append(common_fields(), [
      schema.Required("query", bounded_string(1, 200)),
      schema.Required("caseSensitive", schema.boolean()),
      schema.Required(
        "offset",
        schema.integer() |> schema.with_number_range(0.0, 5000.0),
      ),
      schema.Required(
        "limit",
        schema.integer() |> schema.with_number_range(1.0, 100.0),
      ),
    ]),
  )
}

fn excerpt_schema() -> schema.Schema {
  schema.object(
    list.append(common_fields(), [
      schema.Required("segmentId", bounded_string(1, 500)),
      schema.Required(
        "contextSegments",
        schema.integer() |> schema.with_number_range(0.0, 5.0),
      ),
    ]),
  )
}

fn align_schema() -> schema.Schema {
  schema.object([
    schema.Required("leftPath", bounded_string(1, 4096)),
    schema.Required("leftSha256", bounded_string(64, 64)),
    schema.Required("rightPath", bounded_string(1, 4096)),
    schema.Required("rightSha256", bounded_string(64, 64)),
    schema.Required(
      "maximumBytesEach",
      schema.integer() |> schema.with_number_range(1.0, 5_000_000.0),
    ),
    schema.Required("query", bounded_string(1, 200)),
    schema.Required("caseSensitive", schema.boolean()),
    schema.Required(
      "maximumMatchesPerSide",
      schema.integer() |> schema.with_number_range(1.0, 50.0),
    ),
  ])
}

fn search_decoder() -> decode.Decoder(SearchInput) {
  use path <- decode.field("path", decode.string)
  use expected <- decode.field("expectedSha256", decode.string)
  use maximum <- decode.field("maximumBytes", decode.int)
  use query <- decode.field("query", decode.string)
  use sensitive <- decode.field("caseSensitive", decode.bool)
  use offset <- decode.field("offset", decode.int)
  use limit <- decode.field("limit", decode.int)
  decode.success(SearchInput(
    path,
    expected,
    maximum,
    query,
    sensitive,
    offset,
    limit,
  ))
}

fn excerpt_decoder() -> decode.Decoder(ExcerptInput) {
  use path <- decode.field("path", decode.string)
  use expected <- decode.field("expectedSha256", decode.string)
  use maximum <- decode.field("maximumBytes", decode.int)
  use segment <- decode.field("segmentId", decode.string)
  use context <- decode.field("contextSegments", decode.int)
  decode.success(ExcerptInput(path, expected, maximum, segment, context))
}

fn align_decoder() -> decode.Decoder(AlignInput) {
  use left_path <- decode.field("leftPath", decode.string)
  use left_hash <- decode.field("leftSha256", decode.string)
  use right_path <- decode.field("rightPath", decode.string)
  use right_hash <- decode.field("rightSha256", decode.string)
  use maximum <- decode.field("maximumBytesEach", decode.int)
  use query <- decode.field("query", decode.string)
  use sensitive <- decode.field("caseSensitive", decode.bool)
  use matches <- decode.field("maximumMatchesPerSide", decode.int)
  decode.success(AlignInput(
    left_path,
    left_hash,
    right_path,
    right_hash,
    maximum,
    query,
    sensitive,
    matches,
  ))
}

fn bounded_string(minimum: Int, maximum: Int) -> schema.Schema {
  schema.string() |> schema.with_string_length(minimum, maximum)
}
