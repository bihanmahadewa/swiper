export class Collector {
  async collect() {
    throw new Error("Collector.collect() must be implemented by subclasses");
  }
}
