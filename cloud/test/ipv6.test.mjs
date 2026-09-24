import test from "node:test";
import assert from "node:assert/strict";
import { call, makeEnv } from "./helpers.mjs";

async function fill(env, ips) {
  const statuses = [];
  for (const ip of ips) statuses.push((await call(env, "POST", "/v1/devices", { ip })).status);
  return statuses;
}

test("#52: aynı /64 içindeki '::' yazımları tek blok sayılıyor", async () => {
  const env = makeEnv();
  // Hepsi 2001:db8:0:0::/64 içinde, ama eski bölmede farklı anahtar üretiyordu.
  const ips = [];
  for (let i = 1; i <= 20; i++) ips.push(`2001:db8::${i.toString(16)}`);
  ips.push("2001:db8:0:0:ffff::1");
  ips.push("2001:0DB8:0000:0000:1:2:3:4");
  const statuses = await fill(env, ips);
  assert.deepEqual(statuses.slice(0, 20), Array(20).fill(200));
  assert.deepEqual(statuses.slice(20), [429, 429]);
});

test("#52: farklı /64 blokları birbirini etkilemiyor", async () => {
  const env = makeEnv();
  await fill(env, Array.from({ length: 20 }, (_, i) => `2001:db8:0:1::${i + 1}`));
  const r = await call(env, "POST", "/v1/devices", { ip: "2001:db8:0:2::1" });
  assert.equal(r.status, 200);
  // '::' ile başlayan kısa yazım da açılıyor: ::1 ile 0:0:0:0::2 aynı blok.
  const env2 = makeEnv();
  await fill(env2, Array.from({ length: 20 }, (_, i) => `::${i + 1}`));
  assert.equal((await call(env2, "POST", "/v1/devices", { ip: "0:0:0:0::abcd" })).status, 429);
});

test("#52: IPv4-eşlemeli IPv6 adresi IPv4 olarak sayılıyor", async () => {
  const env = makeEnv();
  await fill(env, Array(20).fill("198.51.100.9"));
  const r = await call(env, "POST", "/v1/devices", { ip: "::ffff:198.51.100.9" });
  assert.equal(r.status, 429);
});
