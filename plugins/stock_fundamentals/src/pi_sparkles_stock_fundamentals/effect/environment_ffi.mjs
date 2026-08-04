export function read_product() {
  return process.env.SEC_USER_AGENT_PRODUCT ?? "";
}

export function read_contact() {
  return process.env.SEC_USER_AGENT_CONTACT ?? "";
}
