/**
 * Makes gift codes and stores them in the database in server/.env (the one
 * api.tryglyf.com uses), then prints them as CSV. Each code works once.
 *
 *   npx tsx scripts/make-codes.ts --plan max --days 30 --count 100 --note "testers, a month"
 *
 * Nothing here is committed: the codes are in the database and in whatever
 * file the output is sent to.
 */
import "../src/env.js";
import { Codes, makeCode } from "../src/lib/codes.js";

function arg(name: string, fallback?: string): string {
  const i = process.argv.indexOf(`--${name}`);
  const value = i >= 0 ? process.argv[i + 1] : fallback;
  if (value === undefined) throw new Error(`--${name} is needed`);
  return value;
}

const plan = arg("plan", "max");
const days = Number(arg("days"));
const count = Number(arg("count"));
const note = arg("note", "");
if (plan !== "plus" && plan !== "max") throw new Error("--plan is plus or max");
if (!Number.isInteger(days) || days <= 0) throw new Error("--days is a whole number of days");
if (!Number.isInteger(count) || count <= 0 || count > 5000) throw new Error("--count is 1 to 5000");

const codes = new Codes();
if (!codes.enabled) throw new Error("DATABASE_URL isn't set in server/.env");

const made: string[] = [];
while (made.length < count) {
  const batch = new Set<string>();
  while (batch.size < count - made.length) {
    const code = makeCode();
    if (!made.includes(code)) batch.add(code);
  }
  // A clash with a code already in the table is skipped; make another.
  made.push(...await codes.add([...batch], plan, days, note));
}

console.log("code,plan,days");
for (const code of made) console.log(`${code},${plan},${days}`);
