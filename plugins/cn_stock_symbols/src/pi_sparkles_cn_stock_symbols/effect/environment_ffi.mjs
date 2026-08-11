export function read_token() { return process.env.TUSHARE_TOKEN ?? ""; }
export function read_now_milliseconds() { return Date.now(); }
