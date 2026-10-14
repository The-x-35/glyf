import { describe, expect, it } from "vitest";
import { profileBlock, tidyWritten } from "../src/lib/act.js";

describe("vault details as stand-ins (14 Oct 2026)", () => {
  it("tells the model to copy a braced stand-in as it is", () => {
    const block = profileBlock({ name: "{name}", "work email": "{work email}" });
    expect(block).toContain("work email: {work email}");
    expect(block).toContain("braces included");
  });
  it("says nothing extra for old clients that send values", () => {
    expect(profileBlock({ name: "Alex Kim" })).not.toContain("braces");
  });
  it("keeps a stand-in where a name slot was left", () => {
    expect(tidyWritten("Thanks,\n[Your Name]", { name: "{name}" })).toBe("Thanks,\n{name}");
  });
});
