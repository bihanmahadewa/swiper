/**
 * @typedef {Object} RawEvent
 * @property {string} eventId
 * @property {string} timestampStart
 * @property {string | null} timestampEnd
 * @property {number | null} durationMs
 * @property {string} source
 * @property {string} eventType
 * @property {string | null} appBundleId
 * @property {string | null} appName
 * @property {string | null} windowTitle
 * @property {string | null} url
 * @property {string | null} documentPath
 * @property {Record<string, unknown>} rawPayload
 * @property {number} confidence
 */

/**
 * @typedef {Object} InferenceExplanation
 * @property {string} label
 * @property {string[]} reasons
 * @property {number} confidence
 */

/**
 * @typedef {Object} Session
 * @property {string} sessionId
 * @property {string} day
 * @property {string} timestampStart
 * @property {string} timestampEnd
 * @property {number} durationMs
 * @property {string | null} dominantAppBundleId
 * @property {string | null} dominantAppName
 * @property {string | null} dominantWindowTitle
 * @property {string | null} dominantUrl
 * @property {string | null} dominantDocumentPath
 * @property {string} taskLabel
 * @property {InferenceExplanation} explanation
 * @property {string[]} rawEventIds
 */

/**
 * @typedef {Object} EntityRef
 * @property {string} type
 * @property {string} key
 * @property {string} label
 * @property {Record<string, unknown>} properties
 */

/**
 * @typedef {Object} GraphNode
 * @property {string} nodeId
 * @property {string} nodeType
 * @property {string} key
 * @property {string} label
 * @property {Record<string, unknown>} properties
 */

/**
 * @typedef {Object} GraphEdge
 * @property {string} edgeId
 * @property {string} edgeType
 * @property {string} fromNodeId
 * @property {string} toNodeId
 * @property {string | null} sessionId
 * @property {Record<string, unknown>} properties
 */

export {};
