pub fn cancel_switch(target_session_file: String) -> Bool {
  target_session_file == "/blocked-session.jsonl"
}

pub fn skip_fork_restore(entry_id: String) -> Bool {
  entry_id == "skip-restore"
}
