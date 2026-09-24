import test from "node:test";
import assert from "node:assert/strict";
import { call, makeEnv, register } from "./helpers.mjs";

test("#51: eşzamanlı isteklerde sayaç artışı kaybolmuyor", async () => {
  const env = makeEnv();
  const dev = await register(env);
  env.DB.interleave = true;
  const results = await Promise.all(
    Array.from({ length: 45 }, () => call(env, "GET", "/v1/summary", { auth: dev })),
  );
  const ok = results.filter((r) => r.status === 200).length;
  const limited = results.filter((r) => r.status === 429).length;
  assert.equal(ok, 30);
  assert.equal(limited, 15);
  const row = await env.DB.prepare("SELECT rate_count FROM device WHERE id = ?").bind(dev.deviceId).first();
  assert.equal(row.rate_count, 30);
});

test("#51: pencere dolunca yeni pencere açılıyor", async () => {
  const env = makeEnv();
  const dev = await register(env);
  for (let i = 0; i < 30; i++) await call(env, "GET", "/v1/summary", { auth: dev });
  assert.equal((await call(env, "GET", "/v1/summary", { auth: dev })).status, 429);
  // Pencereyi geriye çek: bir dakikadan eski.
  await env.DB.prepare("UPDATE device SET rate_window_start = rate_window_start - 61000 WHERE id = ?")
    .bind(dev.deviceId)
    .run();
  assert.equal((await call(env, "GET", "/v1/summary", { auth: dev })).status, 200);
  const row = await env.DB.prepare("SELECT rate_count FROM device WHERE id = ?").bind(dev.deviceId).first();
  assert.equal(row.rate_count, 1);
});
