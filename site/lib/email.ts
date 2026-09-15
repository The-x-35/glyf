/** Basic email check, shared by the form and the API (the database enforces
 *  the same shape as a CHECK constraint). A shape test, not deliverability. */

const SHAPE = /^[a-z0-9._%+-]{1,64}@[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)*\.[a-z]{2,}$/i;

export function normalizeEmail(raw: string): string {
  return raw.trim().toLowerCase();
}

/** Null when the address looks fine; otherwise a short, human reason. */
export function emailProblem(raw: string): string | null {
  const email = normalizeEmail(raw);
  if (!email) return "Enter your email.";
  if (email.length > 254) return "That email is too long.";
  if (!email.includes("@")) return "That email is missing an @.";
  if (email.includes("..")) return "That email has two dots in a row.";
  const [local, domain = ""] = email.split("@");
  if (!local || !domain.includes(".")) return "That email doesn't look complete.";
  if (local.startsWith(".") || local.endsWith(".")) return "That email doesn't look right.";
  if (!SHAPE.test(email)) return "That email doesn't look right.";
  return null;
}
