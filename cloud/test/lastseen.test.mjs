import test from "node:test";
import assert from "node:assert/strict";
import { call, makeEnv, register, sample } from "./helpers.mjs";

test("#57: yüklemede last_seen_at yalnızca bir kez yazılıyor", async () => {
  const env = makeEnv();
  const dev = await register(env);
  const writes = [];
  env.DB.hook = (sql) => {
    if (/^\s*UPDATE device/i.test(sql)) writes.push(sql);
  };
  const r = await call(env, "POST", "/v1/samples", { auth: dev, body: { samples: [sample(5)], plan: "max" } });
  assert.equal(r.status, 200);
  assert.equal(writes.filter((s) => s.includes("last_seen_at")).length, 1);

  const row = await env.DB.prepare("SELECT plan, last_seen_at FROM device WHERE id = ?").bind(dev.deviceId).first();
  assert.equal(row.plan, "max");
  assert.ok(row.last_seen_at > 0);

  // Plan gelmezse ya da aynıysa plan için ek yazım yok.
  writes.length = 0;
  await call(env, "POST", "/v1/samples", { auth: dev, body: { samples: [sample(6)] } });
  await call(env, "POST", "/v1/samples", { auth: dev, body: { samples: [sample(7)], plan: "max" } });
  const planWrites = writes.filter((s) => s.includes("SET plan"));
  assert.equal(planWrites.length, 1); // yalnızca ikincisi denedi, o da koşulla hiçbir satırı değiştirmedi
  const again = await env.DB.prepare("SELECT plan FROM device WHERE id = ?").bind(dev.deviceId).first();
  assert.equal(again.plan, "max");
});
