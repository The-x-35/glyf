import { signedInApp } from "./helpers.js";
import { beforeAll, describe, expect, it } from "vitest";
import { env } from "../src/env.js";
import { asksForTheirs, detailByRules } from "../src/lib/details.js";

beforeAll(() => {
  env.mockAI = true;
});

const all = ["address", "phone", "email", "upi", "name", "wallet", "link", "social", "gst"];

describe("saved details the sentence leads into", () => {
  it("hears first-person asks in everyday words", () => {
    expect(detailByRules("sure, my address is", all)).toBe("address");
    expect(detailByRules("haan ship it to", all)).toBe("address");
    expect(detailByRules("ok here's my number:", all)).toBe("phone");
    expect(detailByRules("just gpay me on", all)).toBe("upi");
    expect(detailByRules("my upi id", all)).toBe("upi");
    expect(detailByRules("you can email me at", all)).toBe("email");
    expect(detailByRules("sure! my insta is", all)).toBe("social");
    expect(detailByRules("our gstin is", all)).toBe("gst");
  });

  it("stays quiet for questions to someone else, typed details, and kinds not saved", () => {
    expect(detailByRules("what's your address?", all)).toBeNull();
    expect(detailByRules("send me ur upi", all)).toBeNull();
    expect(detailByRules("my address is 12 Hill Road, Bandra", all)).toBeNull();
    expect(detailByRules("my number is", ["address"])).toBeNull();
    expect(detailByRules("the address was wrong yesterday", all)).toBeNull();
  });

  it("knows a request for someone else's detail from sharing one's own", () => {
    expect(asksForTheirs("whats your address btw i need to send the invite")).toBe(true);
    expect(asksForTheirs("send me ur upi id")).toBe(true);
    expect(asksForTheirs("what's her new number")).toBe(true);
    expect(asksForTheirs("cool just drop it off at")).toBe(false);
    expect(asksForTheirs("sure thing, heres how you can reach me")).toBe(false);
    expect(asksForTheirs("your place or mine tonight")).toBe(false);
  });

  it("answers /suggest with the kind, never a value", async () => {
    const app = signedInApp();
    const res = await app.inject({
      method: "POST", url: "/suggest",
      payload: { text: "yes please ship it to", deviceId: "details-test", kinds: ["address", "upi"] },
    });
    expect(res.json()).toMatchObject({ ok: true, suggestion: { intent: "detail", field: "address" } });
    const none = await app.inject({
      method: "POST", url: "/suggest",
      payload: { text: "yes please ship it to", deviceId: "details-test" },
    });
    expect(none.json().suggestion?.intent).not.toBe("detail");
  });
});
