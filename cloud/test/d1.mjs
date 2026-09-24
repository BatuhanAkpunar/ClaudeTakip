// node:sqlite üstünde küçük bir D1 taklidi. Yalnızca Worker'ın kullandığı
// yüzey: prepare/bind/first/all/run ve tek işlem içinde batch.
import { DatabaseSync } from "node:sqlite";
import { readFileSync, readdirSync } from "node:fs";
import { fileURLToPath } from "node:url";
import path from "node:path";

const root = path.dirname(path.dirname(fileURLToPath(import.meta.url)));

class Statement {
  constructor(db, sql, args = []) {
    this.db = db;
    this.sql = sql;
    this.args = args;
  }
  bind(...args) {
    for (const a of args) {
      if (a === undefined) throw new Error("D1_TYPE_ERROR: undefined bağlanamaz");
    }
    return new Statement(this.db, this.sql, args);
  }
  prep() {
    this.db.hook?.(this.sql);
    return this.db.raw.prepare(this.sql);
  }
  async first(column) {
    await this.db.pause();
    const row = this.prep().get(...this.args);
    if (!row) return null;
    const plain = { ...row };
    return column ? plain[column] : plain;
  }
  async all() {
    await this.db.pause();
    const results = this.prep().all(...this.args).map((r) => ({ ...r }));
    return { success: true, results, meta: { changes: 0 } };
  }
  async run() {
    await this.db.pause();
    const r = this.prep().run(...this.args);
    return { success: true, results: [], meta: { changes: Number(r.changes) } };
  }
  runSync() {
    const s = this.prep();
    if (s.columns().length > 0) {
      return { success: true, results: s.all(...this.args).map((r) => ({ ...r })), meta: { changes: 0 } };
    }
    const r = s.run(...this.args);
    return { success: true, results: [], meta: { changes: Number(r.changes) } };
  }
}

export class FakeD1 {
  constructor() {
    this.raw = new DatabaseSync(":memory:");
    /** Her prepare'de çağrılır; testler hata enjekte etmek için kullanıyor. */
    this.hook = null;
    this.interleave = false;
  }
  prepare(sql) {
    return new Statement(this, sql);
  }
  /**
   * Gerçek D1'de her sorgu bir ağ turu; eşzamanlı istekler arada birbirinin
   * önüne geçebiliyor. `interleave` açıkken her sorgu çalışmadan önce olay
   * döngüsüne dönüyor ve bu yarışlar testte görünür oluyor.
   */
  async pause() {
    if (this.interleave) await new Promise((r) => setImmediate(r));
  }
  async batch(statements) {
    await this.pause();
    // D1 batch'i tek işlem: biri patlarsa hepsi geri alınıyor.
    this.raw.exec("BEGIN");
    try {
      const out = statements.map((s) => s.runSync());
      this.raw.exec("COMMIT");
      return out;
    } catch (e) {
      this.raw.exec("ROLLBACK");
      throw e;
    }
  }
  exec(sql) {
    this.raw.exec(sql);
  }
}

export function migrationFiles() {
  return readdirSync(path.join(root, "migrations"))
    .filter((f) => /^\d{4}_.*\.sql$/.test(f))
    .sort();
}

/** Taban şema + tüm göçler sırayla. */
export function migratedDb() {
  const db = new FakeD1();
  db.exec(readFileSync(path.join(root, "test/baseline.sql"), "utf8"));
  for (const f of migrationFiles()) {
    db.exec(readFileSync(path.join(root, "migrations", f), "utf8"));
  }
  return db;
}

export function schemaDb() {
  const db = new FakeD1();
  db.exec(readFileSync(path.join(root, "schema.sql"), "utf8"));
  return db;
}

/** Karşılaştırılabilir şema özeti: tablolar, sütunlar, dizinler. */
export function describeSchema(db) {
  const raw = db.raw;
  const out = {};
  const objects = raw
    .prepare("SELECT type, name, tbl_name FROM sqlite_master WHERE name NOT LIKE 'sqlite_%' ORDER BY name")
    .all();
  for (const o of objects) {
    if (o.type === "table") {
      out[`table:${o.name}`] = raw
        .prepare(`PRAGMA table_info(${o.name})`)
        .all()
        .map((c) => `${c.name} ${c.type} notnull=${c.notnull} dflt=${c.dflt_value} pk=${c.pk}`)
        .sort();
    } else if (o.type === "index") {
      const cols = raw.prepare(`PRAGMA index_info(${o.name})`).all().map((c) => c.name);
      out[`index:${o.name}`] = `${o.tbl_name}(${cols.join(",")})`;
    }
  }
  return out;
}
