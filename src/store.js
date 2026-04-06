import { SCHEMA_SQL } from "./schema.js";
import { querySql, runSql } from "./sqlite.js";
import { json, parseJson, sqlQuote } from "./util.js";

export class SwiperStore {
  constructor(dbPath) {
    this.dbPath = dbPath;
  }

  init() {
    runSql(this.dbPath, SCHEMA_SQL);
  }

  insertRawEvents(events) {
    if (!events.length) {
      return;
    }

    const values = events
      .map(
        (event) => `(
          ${sqlQuote(event.eventId)},
          ${sqlQuote(event.timestampStart)},
          ${sqlQuote(event.timestampEnd)},
          ${sqlQuote(event.durationMs)},
          ${sqlQuote(event.source)},
          ${sqlQuote(event.eventType)},
          ${sqlQuote(event.appBundleId)},
          ${sqlQuote(event.appName)},
          ${sqlQuote(event.windowTitle)},
          ${sqlQuote(event.url)},
          ${sqlQuote(event.documentPath)},
          ${sqlQuote(json(event.rawPayload))},
          ${sqlQuote(event.confidence)}
        )`,
      )
      .join(",\n");

    runSql(
      this.dbPath,
      `INSERT OR IGNORE INTO raw_events (
        event_id, timestamp_start, timestamp_end, duration_ms, source, event_type,
        app_bundle_id, app_name, window_title, url, document_path, raw_payload, confidence
      ) VALUES ${values};`,
    );
  }

  getRawEventsForDay(day) {
    return querySql(
      this.dbPath,
      `SELECT * FROM raw_events
       WHERE date(timestamp_start) = ${sqlQuote(day)}
       ORDER BY timestamp_start ASC, event_id ASC;`,
    ).map((row) => ({
      eventId: row.event_id,
      timestampStart: row.timestamp_start,
      timestampEnd: row.timestamp_end,
      durationMs: row.duration_ms,
      source: row.source,
      eventType: row.event_type,
      appBundleId: row.app_bundle_id,
      appName: row.app_name,
      windowTitle: row.window_title,
      url: row.url,
      documentPath: row.document_path,
      rawPayload: parseJson(row.raw_payload, {}),
      confidence: row.confidence,
    }));
  }

  replaceSessionsForDay(day, sessions) {
    runSql(this.dbPath, `DELETE FROM sessions WHERE day = ${sqlQuote(day)};`);

    if (!sessions.length) {
      return;
    }

    const values = sessions
      .map(
        (session) => `(
          ${sqlQuote(session.sessionId)},
          ${sqlQuote(session.day)},
          ${sqlQuote(session.timestampStart)},
          ${sqlQuote(session.timestampEnd)},
          ${sqlQuote(session.durationMs)},
          ${sqlQuote(session.dominantAppBundleId)},
          ${sqlQuote(session.dominantAppName)},
          ${sqlQuote(session.dominantWindowTitle)},
          ${sqlQuote(session.dominantUrl)},
          ${sqlQuote(session.dominantDocumentPath)},
          ${sqlQuote(session.taskLabel)},
          ${sqlQuote(json(session.explanation))},
          ${sqlQuote(json(session.rawEventIds))}
        )`,
      )
      .join(",\n");

    runSql(
      this.dbPath,
      `INSERT INTO sessions (
        session_id, day, timestamp_start, timestamp_end, duration_ms,
        dominant_app_bundle_id, dominant_app_name, dominant_window_title,
        dominant_url, dominant_document_path, task_label, explanation, raw_event_ids
      ) VALUES ${values};`,
    );
  }

  getSessionsForDay(day) {
    return querySql(
      this.dbPath,
      `SELECT * FROM sessions
       WHERE day = ${sqlQuote(day)}
       ORDER BY timestamp_start ASC, session_id ASC;`,
    ).map((row) => ({
      sessionId: row.session_id,
      day: row.day,
      timestampStart: row.timestamp_start,
      timestampEnd: row.timestamp_end,
      durationMs: row.duration_ms,
      dominantAppBundleId: row.dominant_app_bundle_id,
      dominantAppName: row.dominant_app_name,
      dominantWindowTitle: row.dominant_window_title,
      dominantUrl: row.dominant_url,
      dominantDocumentPath: row.dominant_document_path,
      taskLabel: row.task_label,
      explanation: parseJson(row.explanation, { label: row.task_label, reasons: [], confidence: 0 }),
      rawEventIds: parseJson(row.raw_event_ids, []),
    }));
  }

  upsertGraph(nodes, edges, day) {
    const sessionIds = querySql(
      this.dbPath,
      `SELECT session_id FROM sessions WHERE day = ${sqlQuote(day)};`,
    ).map((row) => row.session_id);

    if (sessionIds.length) {
      runSql(
        this.dbPath,
        `DELETE FROM graph_edges WHERE session_id IN (${sessionIds.map(sqlQuote).join(",")});`,
      );
    }

    const nodeValues = nodes
      .map(
        (node) => `(
          ${sqlQuote(node.nodeId)},
          ${sqlQuote(node.nodeType)},
          ${sqlQuote(node.key)},
          ${sqlQuote(node.label)},
          ${sqlQuote(json(node.properties))}
        )`,
      )
      .join(",\n");

    if (nodeValues) {
      runSql(
        this.dbPath,
        `INSERT INTO graph_nodes (node_id, node_type, node_key, label, properties)
         VALUES ${nodeValues}
         ON CONFLICT(node_key) DO UPDATE SET
           label = excluded.label,
           properties = excluded.properties;`,
      );
    }

    if (!edges.length) {
      return;
    }

    const edgeValues = edges
      .map(
        (edge) => `(
          ${sqlQuote(edge.edgeId)},
          ${sqlQuote(edge.edgeType)},
          ${sqlQuote(edge.fromNodeId)},
          ${sqlQuote(edge.toNodeId)},
          ${sqlQuote(edge.sessionId)},
          ${sqlQuote(json(edge.properties))}
        )`,
      )
      .join(",\n");

    runSql(
      this.dbPath,
      `INSERT OR REPLACE INTO graph_edges (
        edge_id, edge_type, from_node_id, to_node_id, session_id, properties
      ) VALUES ${edgeValues};`,
    );
  }
}
