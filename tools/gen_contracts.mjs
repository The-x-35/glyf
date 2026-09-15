#!/usr/bin/env node
// §7/§3: shared/contracts is the single source of truth — Swift structs,
// Dart classes, and zod schemas are GENERATED, never hand-written twice.
// Purpose-built for this repo's schema shapes (flat objects, nested objects,
// string arrays, nullable unions, enums, date-time). Rerun after editing
// shared/contracts/*.schema.json:  node tools/gen_contracts.mjs
import { readFileSync, writeFileSync, readdirSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const CONTRACTS = join(ROOT, "shared", "contracts");

const schemas = readdirSync(CONTRACTS)
  .filter(f => f.endsWith(".schema.json"))
  .map(f => JSON.parse(readFileSync(join(CONTRACTS, f), "utf8")));

const HEADER = "GENERATED from shared/contracts — do not edit (tools/gen_contracts.mjs)";

// ---------- helpers ----------
const pascal = s => s.charAt(0).toUpperCase() + s.slice(1);

function propType(prop) {
  // returns {swift, dart, zod, optional}
  if (Array.isArray(prop.type) && prop.type.includes("null")) {
    const inner = propType({ ...prop, type: prop.type.find(t => t !== "null") });
    return { ...inner, optional: true };
  }
  if (prop.oneOf) {
    const nonNull = prop.oneOf.find(o => o.type !== "null");
    const inner = propType(nonNull);
    return { ...inner, optional: true };
  }
  switch (prop.type) {
    case "string":
      if (prop.format === "date-time")
        return { swift: "Date", dart: "DateTime", zod: "z.string()", optional: false, date: true };
      return { swift: "String", dart: "String", zod: enumZod(prop), optional: false };
    case "integer":
      return { swift: "Int", dart: "int", zod: "z.number().int()", optional: false };
    case "number":
      return { swift: "Double", dart: "double", zod: "z.number()", optional: false };
    case "boolean":
      return { swift: "Bool", dart: "bool", zod: "z.boolean()", optional: false };
    case "array": {
      const inner = propType(prop.items ?? { type: "string" });
      return {
        swift: `[${inner.swift}]`, dart: `List<${inner.dart}>`,
        zod: `z.array(${inner.zod})`, optional: false, arrayOf: inner,
      };
    }
    case "object":
      if (!prop.properties) {
        // Generic payload objects: string maps in practice (§7 payloads).
        return {
          swift: "[String: String]", dart: "Map<String, String>",
          zod: "z.record(z.string(), z.string())", optional: false, freeform: true,
        };
      }
      return { nested: true, optional: false };
    default:
      return { swift: "String", dart: "String", zod: "z.string()", optional: false };
  }
}

function enumZod(prop) {
  if (prop.enum) return `z.enum([${prop.enum.map(e => JSON.stringify(e)).join(", ")}])`;
  if (prop.const !== undefined) return `z.literal(${JSON.stringify(prop.const)})`;
  return "z.string()";
}

// ---------- walk schemas, collect types ----------
const types = []; // {name, fields:[{name,type,prop}], parent}
function collect(name, schema) {
  const fields = [];
  for (const [key, prop] of Object.entries(schema.properties ?? {})) {
    const t = propType(prop);
    // oneOf FIRST: a bare `oneOf: [null, object]` also reads as nested, but
    // recursing into the oneOf wrapper yields an empty struct (no properties)
    // and would drop the optionality.
    if (prop.oneOf) {
      const nonNull = prop.oneOf.find(o => o.type !== "null");
      if (nonNull?.type === "object" && nonNull.properties) {
        const childName = `${name}${pascal(key)}`;
        collect(childName, nonNull);
        fields.push({ name: key, swift: childName, dart: childName,
          zod: `${childName}Schema`, optional: true, nested: true });
      } else {
        fields.push({ name: key, ...t });
      }
    } else if (t.nested) {
      const childName = `${name}${pascal(key)}`;
      collect(childName, prop);
      fields.push({ name: key, swift: childName, dart: childName,
        zod: `${childName}Schema`, optional: false, nested: true });
    } else {
      fields.push({ name: key, ...t });
    }
  }
  types.push({ name, fields });
}
for (const schema of schemas) collect(schema.title, schema);

// ---------- Swift ----------
let swift = `import Foundation

/// ${HEADER}
/// Dates are ISO-8601 (IntentStore's encoder/decoder handle the strategy).
`;
for (const t of types) {
  swift += `\nstruct ${t.name}: Codable, Equatable {\n`;
  for (const f of t.fields) {
    swift += `    var ${f.name}: ${f.swift}${f.optional ? "?" : ""}\n`;
  }
  // Explicit memberwise init keeps call sites stable.
  swift += `\n    init(${t.fields.map(f =>
    `${f.name}: ${f.swift}${f.optional ? "? = nil" : ""}`).join(", ")}) {\n`;
  for (const f of t.fields) swift += `        self.${f.name} = ${f.name}\n`;
  swift += "    }\n}\n";
}
// Back-compat aliases: the app code says GlyfIntent/GlyfResult.
swift += `\ntypealias GlyfIntent = Intent\ntypealias GlyfResult = Result_\n`;
swift = swift.replaceAll("struct Result:", "struct Result_:")
             .replaceAll("ResultError", "Result_Error")
             .replaceAll("struct Result_Error", "struct Result_Error");
writeFileSync(join(ROOT, "app/ios/GlyfKeyboard/Bridge/Contracts.generated.swift"), swift);

// ---------- Dart ----------
let dart = `// ${HEADER}\n`;
for (const t of types) {
  const name = t.name === "Result" ? "GlyfResultContract" : t.name === "Intent" ? "GlyfIntentContract" : t.name;
  dart += `\nclass ${name} {\n`;
  for (const f of t.fields) {
    const ty = f.dart === "Result" ? "GlyfResultContract" : f.dart === "Intent" ? "GlyfIntentContract" : f.dart;
    dart += `  final ${ty}${f.optional ? "?" : ""} ${f.name};\n`;
  }
  dart += `  const ${name}({${t.fields.map(f =>
    `${f.optional ? "" : "required "}this.${f.name}`).join(", ")}});\n`;
  dart += `  factory ${name}.fromJson(Map<String, dynamic> j) => ${name}(\n`;
  for (const f of t.fields) {
    let expr;
    if (f.nested) expr = f.optional
      ? `j['${f.name}'] == null ? null : ${f.dart}.fromJson(j['${f.name}'] as Map<String, dynamic>)`
      : `${f.dart}.fromJson(j['${f.name}'] as Map<String, dynamic>)`;
    else if (f.date) expr = `DateTime.parse(j['${f.name}'] as String)`;
    else if (f.freeform) expr = `(j['${f.name}'] as Map).cast<String, String>()`;
    else if (f.arrayOf) expr = `(j['${f.name}'] as List).cast<${f.arrayOf.dart}>()`;
    else expr = `j['${f.name}'] as ${f.dart}${f.optional ? "?" : ""}`;
    dart += `        ${f.name}: ${expr},\n`;
  }
  dart += "      );\n}\n";
}
writeFileSync(join(ROOT, "app/lib/core/contracts.g.dart"), dart);

// ---------- zod ----------
let zod = `// ${HEADER}\nimport { z } from "zod";\n`;
for (const t of types) { // collect() pushes children before parents
  zod += `\nexport const ${t.name}Schema = z.object({\n`;
  for (const f of t.fields) {
    let expr = f.nested ? `${f.zod}` : f.date ? "z.string()" : f.zod;
    if (f.optional) expr += ".nullable()";
    zod += `  ${f.name}: ${expr},\n`;
  }
  zod += "});\n";
}
writeFileSync(join(ROOT, "server/src/schemas/contracts.generated.ts"), zod);

console.log(`generated ${types.length} types → Swift + Dart + zod`);
