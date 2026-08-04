import finance_provenance/assumption.{type Assumption, type AssumptionId}
import finance_provenance/evidence.{type Evidence}
import finance_provenance/identity.{type EvidenceId}
import gleam/list
import gleam/option.{type Option, None, Some}

pub opaque type Manifest {
  Manifest(
    assumptions: List(Assumption),
    evidence: List(Evidence),
    roots: List(EvidenceId),
  )
}

pub type ManifestError {
  ConflictingEvidence(id: String)
  ConflictingAssumption(id: String)
  MissingParent(id: String)
  MissingAssumption(id: String)
  UnknownRoot(id: String)
}

pub fn new() -> Manifest {
  Manifest([], [], [])
}

pub fn assumptions(manifest: Manifest) -> List(Assumption) {
  let Manifest(assumptions, _, _) = manifest
  assumptions
}

pub fn evidence(manifest: Manifest) -> List(Evidence) {
  let Manifest(_, evidence, _) = manifest
  evidence
}

pub fn roots(manifest: Manifest) -> List(EvidenceId) {
  let Manifest(_, _, roots) = manifest
  roots
}

pub fn add_assumption(
  manifest: Manifest,
  item: Assumption,
) -> Result(Manifest, ManifestError) {
  let Manifest(assumptions, evidence, roots) = manifest
  case find_assumption(assumptions, item.id) {
    Some(existing) if existing == item -> Ok(manifest)
    Some(_) -> Error(ConflictingAssumption(assumption.id_value(item.id)))
    None -> Ok(Manifest(list.append(assumptions, [item]), evidence, roots))
  }
}

pub fn add_evidence(
  manifest: Manifest,
  item: Evidence,
) -> Result(Manifest, ManifestError) {
  let Manifest(assumptions, items, roots) = manifest
  case find_evidence(items, item.id) {
    Some(existing) if existing == item -> Ok(manifest)
    Some(_) -> Error(ConflictingEvidence(identity.evidence_id_value(item.id)))
    None ->
      case first_missing_parent(items, item.parents) {
        Some(parent) -> Error(MissingParent(identity.evidence_id_value(parent)))
        None ->
          case first_missing_assumption(assumptions, item.assumptions) {
            Some(id) -> Error(MissingAssumption(assumption.id_value(id)))
            None -> Ok(Manifest(assumptions, list.append(items, [item]), roots))
          }
      }
  }
}

pub fn add_root(
  manifest: Manifest,
  id: EvidenceId,
) -> Result(Manifest, ManifestError) {
  let Manifest(assumptions, items, roots) = manifest
  case find_evidence(items, id), contains_id(roots, id) {
    None, _ -> Error(UnknownRoot(identity.evidence_id_value(id)))
    Some(_), True -> Ok(manifest)
    Some(_), False -> Ok(Manifest(assumptions, items, list.append(roots, [id])))
  }
}

pub fn merge(
  left: Manifest,
  right: Manifest,
) -> Result(Manifest, ManifestError) {
  case list.try_fold(assumptions(right), left, add_assumption) {
    Error(error) -> Error(error)
    Ok(with_assumptions) ->
      case list.try_fold(evidence(right), with_assumptions, add_evidence) {
        Error(error) -> Error(error)
        Ok(combined) -> list.try_fold(roots(right), combined, add_root)
      }
  }
}

fn first_missing_assumption(
  assumptions: List(Assumption),
  ids: List(AssumptionId),
) -> Option(AssumptionId) {
  case ids {
    [] -> None
    [id, ..rest] ->
      case find_assumption(assumptions, id) {
        Some(_) -> first_missing_assumption(assumptions, rest)
        None -> Some(id)
      }
  }
}

fn find_assumption(
  assumptions: List(Assumption),
  id: AssumptionId,
) -> Option(Assumption) {
  case assumptions {
    [] -> None
    [item, ..] if item.id == id -> Some(item)
    [_, ..rest] -> find_assumption(rest, id)
  }
}

fn first_missing_parent(
  items: List(Evidence),
  parents: List(EvidenceId),
) -> Option(EvidenceId) {
  case parents {
    [] -> None
    [parent, ..rest] ->
      case find_evidence(items, parent) {
        Some(_) -> first_missing_parent(items, rest)
        None -> Some(parent)
      }
  }
}

fn find_evidence(items: List(Evidence), id: EvidenceId) -> Option(Evidence) {
  case items {
    [] -> None
    [item, ..] if item.id == id -> Some(item)
    [_, ..rest] -> find_evidence(rest, id)
  }
}

fn contains_id(ids: List(EvidenceId), id: EvidenceId) -> Bool {
  list.any(ids, fn(candidate) { candidate == id })
}
