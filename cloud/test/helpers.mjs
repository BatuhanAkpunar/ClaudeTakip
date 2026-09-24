import worker from "../src/index.ts";
import { migratedDb } from "./d1.mjs";

export const BASE = "https://sync.test";
export const KEY_A = "a".repeat(64);
export const KEY_B = "b".repeat(64);
export const KEY_C = "c".repeat(64);

export function makeEnv(extra = {}) {
  return { DB: migratedDb(), IP_SALT: "test-salt", ...extra };
}

export async function call(env, method, path, { auth, key, ip = "203.0.113.7", body, headers = {} } = {}) {
  const h = { "cf-connecting-ip": ip, ...headers };
  if (auth) h.authorization = `Bearer ${auth.deviceId}.${auth.secret}`;
  if (key) h["x-account-key"] = key;
  const init = { method, headers: h };
  if (body !== undefined) {
    init.body = typeof body === "string" ? body : JSON.stringify(body);
    h["content-type"] = "application/json";
  }
  const res = await worker.fetch(new Request(BASE + path, init), env, {});
  const text = await res.text();
  let data = null;
  try {
    data = JSON.parse(text);
  } catch {}
  return { status: res.status, data, text, headers: res.headers };
}

export async function register(env, ip = "203.0.113.7") {
  const r = await call(env, "POST", "/v1/devices", { ip });
  if (r.status !== 200) throw new Error(`kayıt başarısız: ${r.status} ${r.text}`);
  return r.data;
}

export function sample(t, fiveHour = 10, sevenDay = 20) {
  return { t, fiveHour, sevenDay, extra: null };
}
