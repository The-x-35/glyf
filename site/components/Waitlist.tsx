"use client";

import { useEffect, useId, useRef, useState } from "react";
import { emailProblem, normalizeEmail } from "@/lib/email";
import { CheckIcon } from "./kb/icons";

const KEY = "glyf-waitlist";

export default function Waitlist({ source }: { source: string }) {
  const id = useId();
  const [email, setEmail] = useState("");
  const [state, setState] = useState<"idle" | "busy" | "done" | "error">("idle");
  const [msg, setMsg] = useState("");
  const [already, setAlready] = useState(false);
  const honey = useRef<HTMLInputElement>(null);

  useEffect(() => {
    try {
      if (localStorage.getItem(KEY)) setState("done");
    } catch {}
    // Both forms (hero + footer) mirror each other.
    const joined = () => setState("done");
    const reset = () => {
      setEmail("");
      setAlready(false);
      setState("idle");
    };
    window.addEventListener("glyf:joined", joined);
    window.addEventListener("glyf:reset", reset);
    return () => {
      window.removeEventListener("glyf:joined", joined);
      window.removeEventListener("glyf:reset", reset);
    };
  }, []);

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
      try {
        localStorage.setItem(KEY, "1");
      } catch {}
      setAlready(Boolean(body.already));
      setState("done");
      window.dispatchEvent(new Event("glyf:joined"));
    } catch (err) {
      setState("error");
      setMsg(err instanceof Error ? err.message : "Couldn't join right now. Try again in a bit.");
    }
  }

  if (state === "done") {
    return (
      <p className="wl-done" role="status">
        <span className="wl-check"><CheckIcon /></span>
        {already ? "You're already on the list." : "You're on the list. We'll email you when Glyf ships."}
        <button
          type="button"
          className="wl-again"
          onClick={() => {
            try {
              localStorage.removeItem(KEY);
            } catch {}
            window.dispatchEvent(new Event("glyf:reset"));
          }}
        >
          Add another
        </button>
      </p>
    );
  }

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
            if (state === "error") setState("idle");
          }}
          aria-invalid={state === "error"}
          aria-describedby={`${id}-msg`}
        />
        <input ref={honey} className="wl-hp" name="company" tabIndex={-1} autoComplete="off" aria-hidden />
        <button type="submit" disabled={state === "busy"}>
          {state === "busy" ? "Joining…" : "Join the waitlist"}
        </button>
      </div>
      <p id={`${id}-msg`} className="wl-msg" role="status">{state === "error" ? msg : ""}</p>
    </form>
  );
}
