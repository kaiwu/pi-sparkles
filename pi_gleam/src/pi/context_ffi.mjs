export function ui(context) {
  return context.ui;
}

export function cwd(context) {
  return context.cwd;
}

export function mode(context) {
  return context.mode;
}

export function has_ui(context) {
  return context.hasUI;
}

export function is_idle(context) {
  return context.isIdle();
}

export function is_project_trusted(context) {
  return context.isProjectTrusted();
}

export function has_signal(context) {
  return context.signal !== undefined;
}

export function signal(context) {
  return context.signal;
}

export function signal_aborted(signal) {
  return signal.aborted;
}

export function abort(context) {
  context.abort();
}

export function has_pending_messages(context) {
  return context.hasPendingMessages();
}

export function shutdown(context) {
  context.shutdown();
}

export function compact(context) {
  context.compact();
}

export function get_system_prompt(context) {
  return context.getSystemPrompt();
}

export function get_context_usage(context) {
  return context.getContextUsage();
}

export function get_scoped_models(context) {
  return context.scopedModels;
}

export function wait_for_idle(context) {
  return context.waitForIdle();
}

export function new_session(context) {
  return context.newSession();
}

export function fork(context, entryId, position) {
  return context.fork(entryId, { position });
}

export function navigate_tree(context, targetId, summarize) {
  return context.navigateTree(targetId, { summarize });
}

export function switch_session(context, sessionPath) {
  return context.switchSession(sessionPath);
}

export function reload(context) {
  return context.reload();
}
