export function read_product() {
  return process.env.CNINFO_USER_AGENT_PRODUCT ?? "";
}

export function read_contact() {
  return process.env.CNINFO_USER_AGENT_CONTACT ?? "";
}

export function read_now_milliseconds() {
  return Date.now();
}
