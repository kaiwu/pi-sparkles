export function rejected_inspector() {
  return Promise.reject(new Error("private inspector effect failure"));
}
