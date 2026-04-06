import { createId, hostnameFromUrl } from "./util.js";

export class EntityExtractor {
  buildGraph(sessions) {
    const nodeMap = new Map();
    const edgeMap = new Map();

    for (const [index, session] of sessions.entries()) {
      const sessionNode = upsertNode(nodeMap, "Session", session.sessionId, session.taskLabel, {
        day: session.day,
        timestampStart: session.timestampStart,
        timestampEnd: session.timestampEnd,
        durationMs: session.durationMs,
        explanation: session.explanation,
      });

      const dayNode = upsertNode(nodeMap, "Day", session.day, session.day, { day: session.day });
      upsertEdge(edgeMap, "PART_OF_DAY", sessionNode.nodeId, dayNode.nodeId, session.sessionId, {});

      if (index > 0) {
        upsertEdge(edgeMap, "PRECEDES", sessions[index - 1].sessionId, session.sessionId, null, {});
      }

      if (session.dominantAppBundleId || session.dominantAppName) {
        const appKey = session.dominantAppBundleId ?? session.dominantAppName;
        const appNode = upsertNode(nodeMap, "App", appKey, session.dominantAppName ?? appKey, {
          bundleId: session.dominantAppBundleId,
        });
        upsertEdge(edgeMap, "USED_APP", sessionNode.nodeId, appNode.nodeId, session.sessionId, {});
      }

      if (session.dominantWindowTitle) {
        const windowNode = upsertNode(
          nodeMap,
          "Window",
          `${session.dominantAppBundleId ?? "unknown"}:${session.dominantWindowTitle}`,
          session.dominantWindowTitle,
          {},
        );
        upsertEdge(edgeMap, "FOCUSED_WINDOW", sessionNode.nodeId, windowNode.nodeId, session.sessionId, {});
      }

      const host = hostnameFromUrl(session.dominantUrl);
      if (host) {
        const websiteNode = upsertNode(nodeMap, "Website", host, host, { url: session.dominantUrl });
        upsertEdge(edgeMap, "VISITED_SITE", sessionNode.nodeId, websiteNode.nodeId, session.sessionId, {});
      }

      if (session.dominantDocumentPath) {
        const documentNode = upsertNode(
          nodeMap,
          "Document",
          session.dominantDocumentPath,
          session.dominantDocumentPath.split("/").pop() ?? session.dominantDocumentPath,
          { path: session.dominantDocumentPath },
        );
        upsertEdge(edgeMap, "EDITED_DOCUMENT", sessionNode.nodeId, documentNode.nodeId, session.sessionId, {});

        const project = deriveProjectFromPath(session.dominantDocumentPath);
        if (project) {
          const projectNode = upsertNode(nodeMap, "Project", project, project, {});
          upsertEdge(edgeMap, "RELATED_TO_PROJECT", sessionNode.nodeId, projectNode.nodeId, session.sessionId, {});
        }
      }

      for (const topic of deriveTopics(session)) {
        const topicNode = upsertNode(nodeMap, "Topic", topic, topic, {});
        upsertEdge(edgeMap, "ABOUT_TOPIC", sessionNode.nodeId, topicNode.nodeId, session.sessionId, {});
      }

      for (const person of derivePeople(session)) {
        const personNode = upsertNode(nodeMap, "Person", person, person, {});
        upsertEdge(edgeMap, "MENTIONS_PERSON", sessionNode.nodeId, personNode.nodeId, session.sessionId, {});
      }
    }

    return {
      nodes: [...nodeMap.values()],
      edges: [...edgeMap.values()],
    };
  }
}

function upsertNode(nodeMap, type, key, label, properties) {
  const nodeKey = `${type}:${key}`;
  const existing = nodeMap.get(nodeKey);
  if (existing) {
    existing.label = label;
    existing.properties = { ...existing.properties, ...properties };
    return existing;
  }

  const node = {
    nodeId: createId("node", type, key),
    nodeType: type,
    key: nodeKey,
    label,
    properties,
  };
  nodeMap.set(nodeKey, node);
  return node;
}

function upsertEdge(edgeMap, type, fromNodeId, toNodeId, sessionId, properties) {
  const edgeKey = `${type}:${fromNodeId}:${toNodeId}:${sessionId ?? ""}`;
  if (!edgeMap.has(edgeKey)) {
    edgeMap.set(edgeKey, {
      edgeId: createId("edge", edgeKey),
      edgeType: type,
      fromNodeId,
      toNodeId,
      sessionId,
      properties,
    });
  }
}

function deriveProjectFromPath(documentPath) {
  const segments = documentPath.split("/").filter(Boolean);
  const index = segments.findIndex((segment) => segment === "Developer");
  if (index >= 0 && segments[index + 1]) {
    return segments[index + 1];
  }
  return segments.at(-2) ?? null;
}

function deriveTopics(session) {
  if (Array.isArray(session.topicHints) && session.topicHints.length) {
    return session.topicHints;
  }

  const host = hostnameFromUrl(session.dominantUrl);
  if (!host) {
    return [];
  }

  return host
    .split(".")
    .filter((part) => part.length >= 4 && !GENERIC_HOST_PARTS.has(part))
    .slice(0, 3);
}

const GENERIC_HOST_PARTS = new Set(["www", "com", "app", "docs"]);

function derivePeople(session) {
  return Array.isArray(session.personHints) ? session.personHints.slice(0, 5) : [];
}
