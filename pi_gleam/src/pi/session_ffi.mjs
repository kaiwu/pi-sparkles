export function manager(context) {
  return context.sessionManager;
}

export function cwd(manager) {
  return manager.getCwd();
}

export function directory(manager) {
  return manager.getSessionDir();
}

export function id(manager) {
  return manager.getSessionId();
}

export function file(manager) {
  return manager.getSessionFile();
}

export function leaf_id(manager) {
  return manager.getLeafId();
}

export function entries(manager) {
  return manager.getEntries();
}

export function branch(manager) {
  return manager.getBranch();
}

export function context_entries(manager) {
  return manager.buildContextEntries();
}

export function custom_entries(manager, customType) {
  return manager
    .getBranch()
    .filter((entry) => entry.type === "custom" && entry.customType === customType);
}

export function all_custom_entries(manager, customType) {
  return manager
    .getEntries()
    .filter((entry) => entry.type === "custom" && entry.customType === customType);
}
