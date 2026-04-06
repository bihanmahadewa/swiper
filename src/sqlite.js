import { execFileSync } from "node:child_process";

export function runSql(dbPath, sql) {
  execFileSync("sqlite3", [dbPath, sql], { stdio: "pipe" });
}

export function querySql(dbPath, sql) {
  const output = execFileSync("sqlite3", ["-json", dbPath, sql], {
    encoding: "utf8",
    stdio: "pipe",
  });

  return output.trim() ? JSON.parse(output) : [];
}
