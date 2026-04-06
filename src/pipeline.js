import { EntityExtractor } from "./graph.js";
import { Sessionizer } from "./sessionize.js";
import { SwiperStore } from "./store.js";
import { toDay } from "./util.js";

export class SwiperEngine {
  constructor({ dbPath, collector, sessionizer = new Sessionizer(), entityExtractor = new EntityExtractor() }) {
    this.store = new SwiperStore(dbPath);
    this.collector = collector;
    this.sessionizer = sessionizer;
    this.entityExtractor = entityExtractor;
  }

  init() {
    this.store.init();
  }

  async collectOnce() {
    const events = await this.collector.collect();
    this.store.insertRawEvents(events);
    const days = new Set(events.map((event) => toDay(event.timestampStart)));

    for (const day of days) {
      this.rebuildDay(day);
    }

    return events;
  }

  ingestEvents(events) {
    this.store.insertRawEvents(events);
    const days = new Set(events.map((event) => toDay(event.timestampStart)));
    for (const day of days) {
      this.rebuildDay(day);
    }
  }

  rebuildDay(day) {
    const events = this.store.getRawEventsForDay(day);
    const sessions = this.sessionizer.buildSessions(events);
    this.store.replaceSessionsForDay(day, sessions);
    const graph = this.entityExtractor.buildGraph(sessions);
    this.store.upsertGraph(graph.nodes, graph.edges, day);
    return { events, sessions, graph };
  }
}
