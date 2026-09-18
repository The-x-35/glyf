import { signedInApp } from "./helpers.js";
import { beforeAll, describe, expect, it } from "vitest";
import { env } from "../src/env.js";
import { detailByRules } from "../src/lib/details.js";

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
