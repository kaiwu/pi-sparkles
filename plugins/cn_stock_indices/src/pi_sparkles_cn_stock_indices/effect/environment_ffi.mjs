export function read_contact() {
  return process.env.AGENT_CONTACT ?? "";
}

export function read_now_milliseconds() {
  return Date.now();
}
