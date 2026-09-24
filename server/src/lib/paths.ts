import { existsSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

/** Where the shipped JSON registries live.
 *
 *  Locally the JSON sits next to the code (`src/registry/<name>`), so the
 *  module-relative path wins and nothing changes. A serverless build can move
 *  or bundle the code without moving the JSON, so we also look for the copies
 *  the deploy keeps next to the working directory (`vercel.json` ships
 *  `src/registry/**` with the function) and honour an explicit override.
 *  Resolution happens on the first call, never at import time. */

const HERE = dirname(fileURLToPath(import.meta.url));

export type RegistryName = "glyfs" | "tools" | "stickers";

const memo = new Map<RegistryName, string>();

export function registryDir(name: RegistryName): string {
  const hit = memo.get(name);
  if (hit) return hit;
  const dir = resolveRegistryDir(name);
  memo.set(name, dir);
  return dir;
}

function resolveRegistryDir(name: RegistryName): string {
  const beside = join(HERE, "..", "registry", name);
  const override = process.env.GLYF_REGISTRY_DIR;
  const candidates = [
    ...(override ? [join(override, name)] : []),
    beside,                                            // src/lib  -> src/registry
    join(HERE, "registry", name),                      // flattened bundle
    resolve(process.cwd(), "src", "registry", name),   // run from server/
    resolve(process.cwd(), "registry", name),
    resolve(process.cwd(), "server", "src", "registry", name), // run from the repo root
  ];
  for (const dir of candidates) {
    if (existsSync(dir)) return dir;
  }
  return beside; // let the caller's readdirSync report the canonical path
}
