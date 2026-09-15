import { neon } from "@neondatabase/serverless";
import { NextResponse } from "next/server";
import { emailProblem, normalizeEmail } from "@/lib/email";

/** Waitlist → Neon Postgres, table `waitlist` (schema: db/waitlist.sql).
 *  DATABASE_URL lives only in server env (.env.local / Vercel settings). */

type Sql = ReturnType<typeof neon<false, false>>;

async function ensureTable(sql: Sql) {
  await sql`CREATE TABLE IF NOT EXISTS waitlist (
    id bigserial PRIMARY KEY,
    email text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    source text,
    country text,
    referrer text
  )`;
  await sql`CREATE UNIQUE INDEX IF NOT EXISTS waitlist_email_unique ON waitlist (lower(email))`;
}

// Light per-instance throttle: a handful of tries per IP per minute.
const hits = new Map<string, number[]>();
function throttled(ip: string) {
  const now = Date.now();
  const recent = (hits.get(ip) ?? []).filter((t) => now - t < 60_000);
  recent.push(now);
  hits.set(ip, recent);
  return recent.length > 8;
}

export async function POST(req: Request) {
  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return NextResponse.json({ ok: false, error: "Bad request." }, { status: 400 });
  }

  // Bots fill the hidden field; tell them it worked and store nothing.
  if (String(body.company ?? "")) return NextResponse.json({ ok: true });

  const ip = req.headers.get("x-forwarded-for")?.split(",")[0]?.trim() || "local";
  if (throttled(ip)) {
    return NextResponse.json({ ok: false, error: "Too many tries. Give it a minute." }, { status: 429 });
  }

  const raw = String(body.email ?? "").slice(0, 320);
  const problem = emailProblem(raw);
  if (problem) return NextResponse.json({ ok: false, error: problem }, { status: 400 });
  const email = normalizeEmail(raw);

  const url = process.env.DATABASE_URL;
  if (!url) {
    return NextResponse.json({ ok: false, error: "The list isn't open yet. Try again soon." }, { status: 503 });
  }

  const sql = neon(url);
  const source = String(body.source ?? "").slice(0, 40) || null;
  const country = req.headers.get("x-vercel-ip-country")?.slice(0, 2) ?? null;
  const referrer = req.headers.get("referer")?.slice(0, 300) ?? null;
  const insert = () => sql`
    INSERT INTO waitlist (email, source, country, referrer)
    VALUES (${email}, ${source}, ${country}, ${referrer})
    ON CONFLICT ((lower(email))) DO NOTHING
    RETURNING id`;

  try {
    let rows: unknown[];
    try {
      rows = (await insert()) as unknown[];
    } catch (err) {
      // First run against an empty database: create the table, then retry.
      if ((err as { code?: string }).code !== "42P01") throw err;
      await ensureTable(sql);
      rows = (await insert()) as unknown[];
    }
    return NextResponse.json({ ok: true, already: rows.length === 0 });
  } catch (err) {
    if ((err as { code?: string }).code === "23514") {
      return NextResponse.json({ ok: false, error: "That email doesn't look right." }, { status: 400 });
    }
    return NextResponse.json({ ok: false, error: "Couldn't join right now. Try again in a bit." }, { status: 502 });
  }
}
