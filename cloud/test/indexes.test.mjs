import test from "node:test";
import assert from "node:assert/strict";
import { migratedDb } from "./d1.mjs";

function indexes(db) {
  return db.raw
    .prepare("SELECT name FROM sqlite_master WHERE type = 'index' AND name NOT LIKE 'sqlite_%'")
    .all()
    .map((r) => r.name);
}

test("#55: birincil anahtarın kopyası olan sample_device_time dizini yok", () => {
  const db = migratedDb();
  assert.ok(!indexes(db).includes("sample_device_time"));
  // Cihaz sorguları hâlâ birincil anahtar dizinini kullanıyor.
  const plan = db.raw
    .prepare("EXPLAIN QUERY PLAN SELECT t FROM sample WHERE device_id = ? AND account_key IS NULL AND t >= ? ORDER BY t")
    .all("x", 0)
    .map((r) => r.detail)
    .join(" ");
  assert.match(plan, /sqlite_autoindex_sample_1|PRIMARY KEY/);
});

test("#54: device_ip_hash dizini yok, yeni kayıt ip_hash yazmıyor", async () => {
  const { makeEnv, register } = await import("./helpers.mjs");
  const env = makeEnv();
  assert.ok(!indexes(env.DB).includes("device_ip_hash"));
  const dev = await register(env);
  const row = await env.DB.prepare("SELECT ip_hash FROM device WHERE id = ?").bind(dev.deviceId).first();
  assert.equal(row.ip_hash, null);
  // Kayıt sınırı hâlâ çalışıyor (günlükten sayılıyor).
  const log = await env.DB.prepare("SELECT COUNT(*) AS n FROM registration_log").first();
  assert.equal(log.n, 1);
});
