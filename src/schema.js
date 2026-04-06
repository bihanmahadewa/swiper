export const SCHEMA_SQL = `
PRAGMA journal_mode = WAL;

CREATE TABLE IF NOT EXISTS raw_events (
  event_id TEXT PRIMARY KEY,
  timestamp_start TEXT NOT NULL,
  timestamp_end TEXT,
  duration_ms INTEGER,
  source TEXT NOT NULL,
  event_type TEXT NOT NULL,
  app_bundle_id TEXT,
  app_name TEXT,
  window_title TEXT,
  url TEXT,
  document_path TEXT,
  raw_payload TEXT NOT NULL,
  confidence REAL NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_raw_events_day ON raw_events(timestamp_start);
CREATE INDEX IF NOT EXISTS idx_raw_events_app ON raw_events(app_bundle_id);

CREATE TABLE IF NOT EXISTS sessions (
  session_id TEXT PRIMARY KEY,
  day TEXT NOT NULL,
  timestamp_start TEXT NOT NULL,
  timestamp_end TEXT NOT NULL,
  duration_ms INTEGER NOT NULL,
  dominant_app_bundle_id TEXT,
  dominant_app_name TEXT,
  dominant_window_title TEXT,
  dominant_url TEXT,
  dominant_document_path TEXT,
  task_label TEXT NOT NULL,
  explanation TEXT NOT NULL,
  raw_event_ids TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_sessions_day ON sessions(day);

CREATE TABLE IF NOT EXISTS graph_nodes (
  node_id TEXT PRIMARY KEY,
  node_type TEXT NOT NULL,
  node_key TEXT NOT NULL UNIQUE,
  label TEXT NOT NULL,
  properties TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_graph_nodes_type ON graph_nodes(node_type);

CREATE TABLE IF NOT EXISTS graph_edges (
  edge_id TEXT PRIMARY KEY,
  edge_type TEXT NOT NULL,
  from_node_id TEXT NOT NULL,
  to_node_id TEXT NOT NULL,
  session_id TEXT,
  properties TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_graph_edges_type ON graph_edges(edge_type);
CREATE INDEX IF NOT EXISTS idx_graph_edges_session ON graph_edges(session_id);
`;
