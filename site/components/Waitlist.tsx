"use client";

import { useId, useRef, useState } from "react";
import { emailProblem, normalizeEmail } from "@/lib/email";
import { CheckIcon } from "./kb/icons";

export default function Waitlist({ source }: { source: string }) {
  const id = useId();
  const [email, setEmail] = useState("");
  const [state, setState] = useState<"idle" | "busy" | "ok" | "error">("idle");
  const [msg, setMsg] = useState("");
  const honey = useRef<HTMLInputElement>(null);

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    if (state === "busy") return;
    const problem = emailProblem(email);
    if (problem) {
      setState("error");
      setMsg(problem);
      return;
    }
    setState("busy");
    try {
      const res = await fetch("/api/waitlist", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ email: normalizeEmail(email), source, company: honey.current?.value ?? "" }),
      });
      const body = await res.json().catch(() => ({}));
      if (!res.ok || !body.ok) throw new Error(body.error ?? "Couldn't join right now. Try again in a bit.");
      setEmail(""); // the address is in, so the box is ready for the next one
      setState("ok");
      setMsg(body.already ? "You're already on the waitlist." : "Email added to the waitlist.");
    } catch (err) {
      setState("error");
      setMsg(err instanceof Error ? err.message : "Couldn't join right now. Try again in a bit.");
    }
  }

  // The form never goes away. Joining says so underneath and empties the box
  // ready for the next address, rather than replacing the thing you just used
  // with a sentence and a link back to it.
  return (
    <form className={`wl${state === "error" ? " wl--error" : ""}`} onSubmit={submit} noValidate>
      <div className="wl-box">
        <label className="sr-only" htmlFor={id}>Email address</label>
        <input
          id={id}
          type="email"
          inputMode="email"
          autoComplete="email"
          autoCapitalize="off"
          spellCheck={false}
          maxLength={254}
          placeholder="you@email.com"
          value={email}
          onChange={(e) => {
            setEmail(e.target.value);
            if (state !== "busy") setState("idle");
          }}
          aria-invalid={state === "error"}
          aria-describedby={`${id}-msg`}
        />
        <input ref={honey} className="wl-hp" name="company" tabIndex={-1} autoComplete="off" aria-hidden />
        <button type="submit" disabled={state === "busy"}>
          {state === "busy" ? "Joining…" : "Join the waitlist"}
        </button>
      </div>
      {state === "ok" ? (
        <p className="wl-ok" role="status">
          <span className="wl-ok-check"><CheckIcon /></span>
          {msg}
        </p>
      ) : (
        <p id={`${id}-msg`} className="wl-msg" role="status">{state === "error" ? msg : ""}</p>
      )}
    </form>
  );
}
