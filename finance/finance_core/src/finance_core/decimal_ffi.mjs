// Exact unsigned integer division primitive for the JavaScript target.
// Decimal policy, scale, signs, and rounding remain in the Gleam domain core.
export function add_unsigned(left, right) {
  return (BigInt(left) + BigInt(right)).toString();
}

export function subtract_unsigned(left, right) {
  return (BigInt(left) - BigInt(right)).toString();
}

export function multiply_unsigned(left, right) {
  return (BigInt(left) * BigInt(right)).toString();
}

export function divide_unsigned(numerator, denominator) {
  const left = BigInt(numerator);
  const right = BigInt(denominator);
  return [(left / right).toString(), (left % right).toString()];
}
