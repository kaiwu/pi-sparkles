import gleam/list
import gleam/string

pub type Risk {
  RecursiveDelete
  PrivilegeEscalation
  WorldWritablePermissions
  OwnershipChange
}

pub type Classification {
  Ordinary
  RequiresConfirmation(risks: List(Risk))
}

pub fn classify(command: String) -> Classification {
  let risks =
    [
      #("rm -rf", RecursiveDelete),
      #("rm -fr", RecursiveDelete),
      #("sudo ", PrivilegeEscalation),
      #("chmod 777", WorldWritablePermissions),
      #("chown 777", OwnershipChange),
    ]
    |> list.fold([], fn(found, rule) {
      let #(term, risk) = rule
      case string.contains(command, term) {
        True -> [risk, ..found]
        False -> found
      }
    })
    |> list.reverse

  case risks {
    [] -> Ordinary
    risks -> RequiresConfirmation(risks)
  }
}

pub fn explain(risks: List(Risk)) -> String {
  risks
  |> list.map(risk_name)
  |> string.join(", ")
}

fn risk_name(risk: Risk) -> String {
  case risk {
    RecursiveDelete -> "recursive deletion"
    PrivilegeEscalation -> "privilege escalation"
    WorldWritablePermissions -> "world-writable permissions"
    OwnershipChange -> "ownership change"
  }
}
