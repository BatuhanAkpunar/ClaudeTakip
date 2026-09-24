/**
 * Testler için D1'in yerine geçen bellek içi SQLite (`node:sqlite`).
 *
 * Bu bir YAKLAŞIM: Worker'ın mantığını ve SQL'ini gerçek bir SQLite üzerinde
 * sınar, Cloudflare çalışma zamanının kendine özgü davranışlarını (tip
 * dönüşümleri, satır ve boyut sınırları, ağ, D1 batch'inin ayrıntıları)
 * sınamaz. Yalnızca src/index.ts'in çağırdığı yüzey var:
 * `prepare(sql).bind(...).first() / .all() / .run()` ve `batch([...])`.
 *
 * Şema, sıfır bir veritabanının tam şeması olan schema.sql'den kuruluyor;
 * migrations/ burada uygulanmıyor.
 */
import { readFileSync } from "node:fs";
import { DatabaseSync } from "node:sqlite";

type Row = Record<string, unknown>;

export interface RunResult {
  success: true;
  results: Row[];
  meta: { changes: number };
}

/**
 * D1'de `bind` deyimi değiştirmez, YENİ bir deyim döner: index.ts tek bir
 * `prepare` sonucunu `map` içinde satır başına ayrı ayrı bağlıyor. SQL de
 * D1'deki gibi ancak çalıştırılırken derleniyor.
 */
class Statement {
  readonly db: DatabaseSync;
  readonly sql: string;
  readonly args: unknown[];

  constructor(db: DatabaseSync, sql: string, args: unknown[]) {
    this.db = db;
    this.sql = sql;
    this.args = args;
  }

  bind(...args: unknown[]): Statement {
    return new Statement(this.db, this.sql, args);
  }

  // node:sqlite satırları prototipsiz nesne olarak veriyor; D1 düz nesne
  // veriyor. Yayılım onları düz nesneye çeviriyor.
  async first(): Promise<Row | null> {
    const row = this.db.prepare(this.sql).get(...(this.args as never[])) as Row | undefined;
    return row ? { ...row } : null;
  }

  async all(): Promise<RunResult> {
    const rows = this.db.prepare(this.sql).all(...(this.args as never[])) as Row[];
    return { success: true, results: rows.map((row) => ({ ...row })), meta: { changes: 0 } };
  }

  async run(): Promise<RunResult> {
    return this.runNow();
  }

  runNow(): RunResult {
    const { changes } = this.db.prepare(this.sql).run(...(this.args as never[]));
    return { success: true, results: [], meta: { changes: Number(changes) } };
  }
}

export interface D1Like {
  prepare(sql: string): Statement;
  batch(statements: Statement[]): Promise<RunResult[]>;
}

/** Şeması kurulmuş, boş, bellek içi bir veritabanı. Her çağrı bağımsız. */
export function makeD1(): D1Like {
  const db = new DatabaseSync(":memory:");
  db.exec(readFileSync(new URL("../schema.sql", import.meta.url), "utf8"));

  return {
    prepare(sql: string): Statement {
      return new Statement(db, sql, []);
    },
    // D1 batch'i tek işlem: biri patlarsa hiçbiri yazılmaz.
    async batch(statements: Statement[]): Promise<RunResult[]> {
      db.exec("BEGIN");
      try {
        const results = statements.map((statement) => statement.runNow());
        db.exec("COMMIT");
        return results;
      } catch (error) {
        db.exec("ROLLBACK");
        throw error;
      }
    },
  };
}
