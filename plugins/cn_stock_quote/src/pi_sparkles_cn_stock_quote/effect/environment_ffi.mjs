export function read_eastmoney_product() {
  return process.env.EASTMONEY_USER_AGENT_PRODUCT ?? "";
}
export function read_eastmoney_contact() {
  return process.env.EASTMONEY_USER_AGENT_CONTACT ?? "";
}
export function read_tushare_token() {
  return process.env.TUSHARE_TOKEN ?? "";
}
export function read_now_milliseconds() {
  return Date.now();
}
