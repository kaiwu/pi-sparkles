import finance_cache_contract
import finance_http/request
import finance_http/response
import finance_provenance/hash
import finance_provenance/identity

pub fn capture(
  request request_value: request.Request,
  response response_value: response.Response,
  provider provider_value: String,
  source source_value: String,
  created_at_milliseconds created_at: Int,
  retrieved_at_milliseconds retrieved_at: Int,
  expires_at_milliseconds expires_at: Int,
  entitlement entitlement_value: String,
  licence licence_value: String,
  validation_state validation: String,
) -> Result(finance_cache_contract.Entry, finance_cache_contract.Error) {
  let safe_identity = request.safe_key(request_value)
  let body = response.body(response_value)
  let assert Ok(request_digest) = hash.text(safe_identity)
  let request_hash = identity.sha256_value(request_digest)
  let assert Ok(content_digest) = hash.text(body)
  let content_hash = identity.sha256_value(content_digest)
  let assert Ok(key_digest) =
    hash.text(provider_value <> "\n" <> source_value <> "\n" <> request_hash)
  finance_cache_contract.entry(
    cache_key_sha256: identity.sha256_value(key_digest),
    provider: provider_value,
    source: source_value,
    request_semantic_sha256: request_hash,
    created_at_milliseconds: created_at,
    retrieved_at_milliseconds: retrieved_at,
    expires_at_milliseconds: expires_at,
    byte_size: response.byte_length(response_value),
    entitlement: entitlement_value,
    licence: licence_value,
    safe_request_identity: safe_identity,
    content_sha256: content_hash,
    validation_state: validation,
    content: body,
  )
}
