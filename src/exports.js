import path from "node:path";
import { createRuntimePaths, ensureRuntimeDirectories, writeJsonFile } from "./runtime.js";

export function exportDailyJson({ dbPath, day, report }) {
  const paths = createRuntimePaths(dbPath);
  ensureRuntimeDirectories(paths);
  const exportPath = path.join(paths.dailyDir, `${day}.json`);
  writeJsonFile(exportPath, report);
  return exportPath;
}
