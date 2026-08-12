export function rejected_fetch() {
  return Promise.reject(new Error("private fetch effect failure"));
}
