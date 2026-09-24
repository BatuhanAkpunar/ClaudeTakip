import test from "node:test";
import assert from "node:assert/strict";
import { call, makeEnv, register } from "./helpers.mjs";

test("#58: dizi gövde 400 alıyor, nesne denetimini geçmiyor", async () => {
  const env = makeEnv();
  const dev = await register(env);
  for (const body of ["[]", '[{"t":1,"fiveHour":1,"sevenDay":1}]']) {
    const r = await call(env, "POST", "/v1/samples", { auth: dev, body });
    assert.equal(r.status, 400);
    assert.deepEqual(r.data, { error: "gövde bir nesne olmalı" });
  }
  // Geçerli boş nesne hâlâ kabul.
  const ok = await call(env, "POST", "/v1/samples", { auth: dev, body: {} });
  assert.equal(ok.status, 200);
  assert.deepEqual(ok.data, { received: 0, rejected: 0, inserted: 0 });
});
