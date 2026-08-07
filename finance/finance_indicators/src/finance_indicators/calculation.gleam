import finance_core/time.{type Date}
import finance_indicators/input.{type InputSnapshot}
import gleam/list

pub type ReceiptSlot(value) {
  Known(value)
  NotApplicable(reason: String)
  Unknown(reason: String)
  NotObtained(reason: String)
  Conflicting(alternatives: List(value))
}

pub type Intermediate {
  Intermediate(name: String, value: String)
}

pub type UnperformedReason {
  InsufficientInputs(available: Int, required: Int)
  InputUnavailable(details: List(String))
  StoppedAfterGap(reason: String)
  ZeroGainAndLoss
}

pub type Output {
  Calculated(
    date: Date,
    value: String,
    unit: String,
    intermediate_values: List(Intermediate),
  )
  Unperformed(date: Date, reason: UnperformedReason, operands: List(String))
}

pub type ResultData {
  ResultData(
    calculation_id: String,
    formula_variant: String,
    seed_variant: ReceiptSlot(String),
    seed_inputs: ReceiptSlot(List(String)),
    inputs: InputSnapshot,
    outputs: List(Output),
    available_operations: List(String),
  )
}

pub type CalculationError {
  RequestCalculationMismatch(expected: String, received: String)
  InvalidInputOrder
  InputOutsideRequestedRange
  ArithmeticFailure(reason: String)
}

pub fn calculated_outputs(value: ResultData) -> List(Output) {
  value.outputs
  |> list.filter(fn(output) {
    case output {
      Calculated(_, _, _, _) -> True
      Unperformed(_, _, _) -> False
    }
  })
}

pub fn unperformed_outputs(value: ResultData) -> List(Output) {
  value.outputs
  |> list.filter(fn(output) {
    case output {
      Calculated(_, _, _, _) -> False
      Unperformed(_, _, _) -> True
    }
  })
}
