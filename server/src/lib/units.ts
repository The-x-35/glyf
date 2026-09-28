/** Unit conversions worked out here, never asked of a model: "5 km in
 *  miles", "100f to c", "how many cm in an inch". They were going to the
 *  model: two seconds, a run, and "approximately" in the answer. Both
 *  keyboards carry the same table (Smart.swift, Smart.kt), so a held space
 *  answers these on the phone with no round trip; the cases in
 *  test/units.test.ts are theirs too. */

type Dim = "length" | "mass" | "temperature" | "volume" | "speed" | "time" | "area";

interface Unit {
  dim: Dim;
  /** How many of the dimension's base unit one of these is (metre, gram,
   *  litre, metre per second, second, square metre). Temperatures convert
   *  through their own rule. */
  size: number;
  /** What it is called in the answer: one, and more than one. */
  one: string;
  many: string;
  /** Everything people type for it, lower case. */
  names: string[];
}

const UNITS: Unit[] = [
  { dim: "length", size: 0.001, one: "mm", many: "mm", names: ["mm", "millimeter", "millimeters", "millimetre", "millimetres"] },
  { dim: "length", size: 0.01, one: "cm", many: "cm", names: ["cm", "cms", "centimeter", "centimeters", "centimetre", "centimetres"] },
  { dim: "length", size: 1, one: "m", many: "m", names: ["m", "meter", "meters", "metre", "metres", "mtr", "mtrs"] },
  { dim: "length", size: 1000, one: "km", many: "km", names: ["km", "kms", "kilometer", "kilometers", "kilometre", "kilometres"] },
  { dim: "length", size: 0.0254, one: "inch", many: "inches", names: ["in", "inch", "inches"] },
  { dim: "length", size: 0.3048, one: "foot", many: "feet", names: ["ft", "foot", "feet"] },
  { dim: "length", size: 0.9144, one: "yard", many: "yards", names: ["yd", "yds", "yard", "yards"] },
  { dim: "length", size: 1609.344, one: "mile", many: "miles", names: ["mi", "mile", "miles"] },
  { dim: "mass", size: 0.001, one: "mg", many: "mg", names: ["mg", "milligram", "milligrams"] },
  { dim: "mass", size: 1, one: "g", many: "g", names: ["g", "gm", "gms", "gram", "grams"] },
  { dim: "mass", size: 1000, one: "kg", many: "kg", names: ["kg", "kgs", "kilo", "kilos", "kilogram", "kilograms"] },
  { dim: "mass", size: 1e6, one: "tonne", many: "tonnes", names: ["tonne", "tonnes"] },
  { dim: "mass", size: 28.349523125, one: "oz", many: "oz", names: ["oz", "ounce", "ounces"] },
  { dim: "mass", size: 453.59237, one: "lb", many: "lb", names: ["lb", "lbs", "pound", "pounds"] },
  { dim: "mass", size: 6350.29318, one: "stone", many: "stone", names: ["st", "stone", "stones"] },
  { dim: "temperature", size: 1, one: "°C", many: "°C", names: ["c", "°c", "celsius", "centigrade", "degrees c", "degree c", "deg c", "degrees celsius"] },
  { dim: "temperature", size: 1, one: "°F", many: "°F", names: ["f", "°f", "fahrenheit", "degrees f", "degree f", "deg f", "degrees fahrenheit"] },
  { dim: "temperature", size: 1, one: "K", many: "K", names: ["k", "kelvin"] },
  { dim: "volume", size: 0.001, one: "ml", many: "ml", names: ["ml", "milliliter", "milliliters", "millilitre", "millilitres"] },
  { dim: "volume", size: 1, one: "litre", many: "litres", names: ["l", "liter", "liters", "litre", "litres", "ltr", "ltrs"] },
  { dim: "volume", size: 0.00492892159375, one: "tsp", many: "tsp", names: ["tsp", "teaspoon", "teaspoons"] },
  { dim: "volume", size: 0.01478676478125, one: "tbsp", many: "tbsp", names: ["tbsp", "tablespoon", "tablespoons"] },
  { dim: "volume", size: 0.0295735295625, one: "fl oz", many: "fl oz", names: ["fl oz", "fluid ounce", "fluid ounces"] },
  { dim: "volume", size: 0.2365882365, one: "cup", many: "cups", names: ["cup", "cups"] },
  { dim: "volume", size: 0.473176473, one: "pint", many: "pints", names: ["pint", "pints"] },
  { dim: "volume", size: 0.946352946, one: "quart", many: "quarts", names: ["quart", "quarts"] },
  { dim: "volume", size: 3.785411784, one: "gallon", many: "gallons", names: ["gal", "gallon", "gallons"] },
  { dim: "speed", size: 1 / 3.6, one: "km/h", many: "km/h", names: ["km/h", "kmh", "kmph", "kph", "kilometers per hour", "kilometres per hour", "km per hour"] },
  { dim: "speed", size: 0.44704, one: "mph", many: "mph", names: ["mph", "miles per hour", "mi/h"] },
  { dim: "speed", size: 1, one: "m/s", many: "m/s", names: ["m/s", "meters per second", "metres per second"] },
  { dim: "speed", size: 1852 / 3600, one: "knot", many: "knots", names: ["knot", "knots"] },
  { dim: "time", size: 1, one: "second", many: "seconds", names: ["s", "sec", "secs", "second", "seconds"] },
  { dim: "time", size: 60, one: "minute", many: "minutes", names: ["min", "mins", "minute", "minutes"] },
  { dim: "time", size: 3600, one: "hour", many: "hours", names: ["h", "hr", "hrs", "hour", "hours"] },
  { dim: "time", size: 86400, one: "day", many: "days", names: ["day", "days"] },
  { dim: "time", size: 604800, one: "week", many: "weeks", names: ["wk", "wks", "week", "weeks"] },
  { dim: "time", size: 31557600, one: "year", many: "years", names: ["yr", "yrs", "year", "years"] },
  { dim: "area", size: 0.09290304, one: "sq ft", many: "sq ft", names: ["sq ft", "sqft", "square feet", "square foot", "ft2"] },
  { dim: "area", size: 1, one: "sq m", many: "sq m", names: ["sq m", "sqm", "square meters", "square metres", "square meter", "square metre", "m2"] },
  { dim: "area", size: 4046.8564224, one: "acre", many: "acres", names: ["acre", "acres"] },
  { dim: "area", size: 10000, one: "hectare", many: "hectares", names: ["ha", "hectare", "hectares"] },
];

const byName = new Map<string, Unit>();
for (const u of UNITS) for (const n of u.names) byName.set(n, u);
/** Longest first, so "fl oz" wins over "oz" and "km/h" over "km". */
const NAME = [...byName.keys()].sort((a, b) => b.length - a.length)
  .map(n => n.replace(/[.*+?^${}()|[\]\\/]/g, "\\$&")).join("|");
const NUMBER = String.raw`(-?(?:\d{1,3}(?:,\d{3})+|\d+)(?:\.\d+)?|-?\.\d+)`;
/** "5 km in miles", "convert 100f to c", "what is 2 cups in ml". */
const DIRECT = new RegExp(
  String.raw`^(?:(?:convert|what\s+is|what's|whats|how\s+much\s+is|how\s+many\s+is)\s+)?${NUMBER}\s*(?:degrees?\s+)?(${NAME})\s+(?:to|in|into|as|in\s+to|=|->|=>)\s+(?:degrees?\s+)?(${NAME})\s*\??$`, "i");
/** "how many cm in an inch", "how many ml are in 2 cups". */
const HOW_MANY = new RegExp(
  String.raw`^how\s+many\s+(${NAME})\s+(?:are\s+)?(?:in|is\s+in|make|makes)\s+(?:(?:a|an|one)\s+|${NUMBER}\s*)(${NAME})\s*\??$`, "i");

export interface UnitAnswer {
  /** "5 km". */
  from: string;
  /** "3.107 miles". */
  to: string;
  /** What goes in the message: "5 km is 3.107 miles". */
  say: string;
}

function toBase(n: number, u: Unit): number {
  if (u.dim !== "temperature") return n * u.size;
  if (u.one === "°F") return (n - 32) * 5 / 9;
  if (u.one === "K") return n - 273.15;
  return n;
}

function fromBase(n: number, u: Unit): number {
  if (u.dim !== "temperature") return n / u.size;
  if (u.one === "°F") return n * 9 / 5 + 32;
  if (u.one === "K") return n + 273.15;
  return n;
}

/** As precise as the size needs: 160,934, 220.5, 32.19, 3.107, 0.0254. */
export function unitNumber(n: number): string {
  if (!Number.isFinite(n)) return "";
  const size = Math.abs(n);
  const decimals = size >= 1000 ? 0 : size >= 100 ? 1 : size >= 10 ? 2 : size >= 1 ? 3 : -1;
  if (decimals >= 0) return n.toLocaleString("en-US", { maximumFractionDigits: decimals });
  return Number(n.toPrecision(3)).toLocaleString("en-US", { maximumFractionDigits: 8 });
}

function named(n: number, u: Unit): string {
  const text = unitNumber(n);
  const name = Math.abs(n) === 1 ? u.one : u.many;
  return u.one.startsWith("°") || u.one === "K" ? `${text}${u.one === "K" ? " K" : name}` : `${text} ${name}`;
}

/** A height in feet and inches: "5 ft 10 in", "5'10", "5 feet 10 inches". */
const FEET_INCHES = new RegExp(
  String.raw`^(?:(?:convert|what\s+is|what's|whats|how\s+much\s+is)\s+)?(\d+)\s*(?:ft|feet|foot|')\s*(\d+(?:\.\d+)?)\s*(?:in|inch|inches|"|'')?\s+(?:to|in|into|as|=)\s+(${NAME})\s*\??$`, "i");

/** Under ten feet, feet come as a height: "5 ft 10 in", not "5.84 feet". */
function asHeight(metres: number): string | null {
  const feet = metres / 0.3048;
  if (feet < 1 || feet >= 10) return null;
  let whole = Math.floor(feet);
  let inches = Math.round((feet - whole) * 12);
  if (inches === 12) { whole += 1; inches = 0; }
  return inches ? `${whole} ft ${inches} in` : `${whole} ft`;
}

/** The conversion asked for, or null when the text is not one. */
export function convertUnits(text: string): UnitAnswer | null {
  const t = text.trim().replace(/\s+/g, " ").replace(/[’‘]/g, "'").toLowerCase();
  const height = t.match(FEET_INCHES);
  if (height) {
    const to = byName.get(height[3]);
    if (!to || to.dim !== "length") return null;
    const feet = Number(height[1]), inches = Number(height[2]);
    const metres = feet * 0.3048 + inches * 0.0254;
    const a = inches ? `${feet} ft ${unitNumber(inches)} in` : `${feet} ft`;
    const b = named(fromBase(metres, to), to);
    return { from: a, to: b, say: `${a} is ${b}` };
  }
  let amount: number, from: Unit | undefined, to: Unit | undefined;
  const direct = t.match(DIRECT);
  if (direct) {
    amount = Number(direct[1].replace(/,/g, ""));
    from = byName.get(direct[2]);
    to = byName.get(direct[3]);
  } else {
    const how = t.match(HOW_MANY);
    if (!how) return null;
    to = byName.get(how[1]);
    amount = how[2] ? Number(how[2].replace(/,/g, "")) : 1;
    from = byName.get(how[3]);
  }
  if (!from || !to || from === to || from.dim !== to.dim || !Number.isFinite(amount)) return null;
  const result = fromBase(toBase(amount, from), to);
  if (!Number.isFinite(result)) return null;
  const a = named(amount, from);
  const b = (to.one === "foot" && asHeight(toBase(amount, from))) || named(result, to);
  return { from: a, to: b, say: `${a} is ${b}` };
}
