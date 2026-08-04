export function notify(ui, message, kind) {
  ui.notify(message, kind);
}

export function select(ui, title, options) {
  return ui.select(title, options);
}

export function confirm(ui, title, message) {
  return ui.confirm(title, message);
}

export function input(ui, title, placeholder) {
  return ui.input(title, placeholder);
}

export function set_status(ui, key, text) {
  ui.setStatus(key, text);
}

export function clear_status(ui, key) {
  ui.setStatus(key, undefined);
}

export function set_working_message(ui, message) {
  ui.setWorkingMessage(message);
}

export function clear_working_message(ui) {
  ui.setWorkingMessage();
}

export function set_working_visible(ui, visible) {
  ui.setWorkingVisible(visible);
}

export function set_hidden_thinking_label(ui, label) {
  ui.setHiddenThinkingLabel(label);
}

export function clear_hidden_thinking_label(ui) {
  ui.setHiddenThinkingLabel();
}

export function set_widget(ui, key, lines, placement) {
  ui.setWidget(key, lines, { placement });
}

export function clear_widget(ui, key) {
  ui.setWidget(key, undefined);
}

export function set_title(ui, title) {
  ui.setTitle(title);
}

export function paste_to_editor(ui, text) {
  ui.pasteToEditor(text);
}

export function set_editor_text(ui, text) {
  ui.setEditorText(text);
}

export function get_editor_text(ui) {
  return ui.getEditorText();
}

export function editor(ui, title, prefill) {
  return ui.editor(title, prefill);
}

export function set_theme(ui, name) {
  return ui.setTheme(name);
}

export function get_all_themes(ui) {
  return ui.getAllThemes();
}

export function get_tools_expanded(ui) {
  return ui.getToolsExpanded();
}

export function set_tools_expanded(ui, expanded) {
  ui.setToolsExpanded(expanded);
}
