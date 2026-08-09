export function read_key_id() {
  return process.env.ALPACA_API_KEY_ID ?? "";
}

export function read_secret_key() {
  return process.env.ALPACA_API_SECRET_KEY ?? "";
}

export function read_product() {
  return process.env.ALPACA_USER_AGENT_PRODUCT ?? "";
}

export function read_contact() {
  return process.env.ALPACA_USER_AGENT_CONTACT ?? "";
}

export function read_now_milliseconds() {
  return Date.now();
}
