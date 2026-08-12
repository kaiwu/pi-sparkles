import finance_core/source.{type SourceRef}
import finance_provenance/evidence.{type Evidence}
import finance_provenance/hash
import finance_provenance/identity.{type EvidenceId, type Sha256}
import finance_provenance/manifest.{type Manifest}
import gleam/javascript/promise.{type Promise}
import gleam/list
import gleam/string

pub type Target {
  Target(
    id: EvidenceId,
    source: SourceRef,
    expected_hash: Sha256,
    expected_bytes: Int,
  )
}

pub opaque type Plan {
  Plan(targets: List(Target), maximum_content_bytes: Int)
}

pub type PlanError {
  InvalidMaximumItems
  InvalidMaximumContentBytes
  EvidenceLimitExceeded(actual: Int, maximum: Int)
  EvidenceContentLimitExceeded(id: EvidenceId, expected: Int, maximum: Int)
}

pub type Outcome(error) {
  Verified(id: EvidenceId)
  ContentMismatch(id: EvidenceId, expected: Sha256, actual: Sha256)
  LengthMismatch(id: EvidenceId, expected: Int, actual: Int)
  FetchFailed(id: EvidenceId, error: error)
  FetchEffectRejected(id: EvidenceId)
  InvalidFetchedContent(id: EvidenceId)
  ContentLimitExceeded(id: EvidenceId, actual: Int, maximum: Int)
}

pub type Report(error) {
  Report(outcomes: List(Outcome(error)))
}

pub type Fetcher(error) =
  fn(Target, Int) -> Promise(Result(String, error))

pub fn plan(
  manifest manifest_value: Manifest,
  maximum_items maximum_items: Int,
  maximum_content_bytes maximum_content_bytes: Int,
) -> Result(Plan, PlanError) {
  let evidence = manifest.evidence(manifest_value)
  let count = list.length(evidence)
  case maximum_items > 0, maximum_content_bytes > 0, count <= maximum_items {
    False, _, _ -> Error(InvalidMaximumItems)
    _, False, _ -> Error(InvalidMaximumContentBytes)
    _, _, False -> Error(EvidenceLimitExceeded(count, maximum_items))
    True, True, True ->
      case
        list.find(evidence, fn(item) {
          item.byte_length > maximum_content_bytes
        })
      {
        Ok(item) ->
          Error(EvidenceContentLimitExceeded(
            item.id,
            item.byte_length,
            maximum_content_bytes,
          ))
        Error(_) -> Ok(Plan(list.map(evidence, target), maximum_content_bytes))
      }
  }
}

pub fn targets(plan: Plan) -> List(Target) {
  let Plan(targets, _) = plan
  targets
}

pub fn verify(
  plan plan_value: Plan,
  using fetch: Fetcher(error),
) -> Promise(Report(error)) {
  let Plan(targets, maximum_content_bytes) = plan_value
  verify_targets(targets, maximum_content_bytes, fetch, [])
}

pub fn inspect(target: Target, content: String) -> Outcome(error) {
  let actual_bytes = string.byte_size(content)
  case actual_bytes == target.expected_bytes {
    False -> LengthMismatch(target.id, target.expected_bytes, actual_bytes)
    True ->
      case hash.text(content) {
        Error(_) -> InvalidFetchedContent(target.id)
        Ok(actual_hash) ->
          case actual_hash == target.expected_hash {
            True -> Verified(target.id)
            False ->
              ContentMismatch(target.id, target.expected_hash, actual_hash)
          }
      }
  }
}

pub fn successful(report: Report(error)) -> Bool {
  let Report(outcomes) = report
  list.all(outcomes, fn(outcome) {
    case outcome {
      Verified(_) -> True
      _ -> False
    }
  })
}

fn target(value: Evidence) -> Target {
  Target(
    id: value.id,
    source: value.source,
    expected_hash: value.content_hash,
    expected_bytes: value.byte_length,
  )
}

fn verify_targets(
  remaining: List(Target),
  maximum_content_bytes: Int,
  fetch: Fetcher(error),
  reversed: List(Outcome(error)),
) -> Promise(Report(error)) {
  case remaining {
    [] -> promise.resolve(Report(list.reverse(reversed)))
    [target, ..rest] -> {
      use fetched <- promise.await(
        fetch(target, maximum_content_bytes)
        |> promise.map(Ok)
        |> promise.rescue(fn(_) { Error(Nil) }),
      )
      let outcome = case fetched {
        Error(_) -> FetchEffectRejected(target.id)
        Ok(Error(error)) -> FetchFailed(target.id, error)
        Ok(Ok(content)) -> {
          let actual = string.byte_size(content)
          case actual > maximum_content_bytes {
            True ->
              ContentLimitExceeded(target.id, actual, maximum_content_bytes)
            False -> inspect(target, content)
          }
        }
      }
      verify_targets(rest, maximum_content_bytes, fetch, [outcome, ..reversed])
    }
  }
}
