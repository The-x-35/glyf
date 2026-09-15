/** Routes the visitor's physical keyboard to ONE demo keyboard: the one they
 *  last touched if it's still on screen, otherwise the most visible one. */

type Entry = {
  el: () => HTMLElement | null;
  key: (e: KeyboardEvent, down: boolean) => boolean;
};

const entries = new Map<string, Entry>();
const downOwner = new Map<string, string>();
let touched: string | null = null;
let installed = false;

function visible(el: HTMLElement) {
  const r = el.getBoundingClientRect();
  const seen = Math.min(r.bottom, window.innerHeight) - Math.max(r.top, 0);
  return r.height > 0 ? Math.max(0, seen) / r.height : 0;
}

function pick(): [string, Entry] | null {
  if (touched) {
    const e = entries.get(touched);
    const el = e?.el();
    if (e && el && visible(el) > 0.1) return [touched, e];
  }
  let best: [string, Entry] | null = null;
  let score = 0.15;
  for (const [id, e] of entries) {
    const el = e.el();
    const v = el ? visible(el) : 0;
    if (v > score) {
      best = [id, e];
      score = v;
    }
  }
  return best;
}

function editable(t: EventTarget | null) {
  const el = t as HTMLElement | null;
  return !!el && (el.isContentEditable || /^(INPUT|TEXTAREA|SELECT)$/.test(el.tagName));
}

function onDown(ev: KeyboardEvent) {
  if (ev.metaKey || ev.ctrlKey || ev.altKey || editable(ev.target)) return;
  const hit = pick();
  if (!hit) return;
  if (hit[1].key(ev, true)) {
    ev.preventDefault();
    downOwner.set(ev.code, hit[0]);
  }
}

function onUp(ev: KeyboardEvent) {
  const id = downOwner.get(ev.code);
  if (!id) return;
  downOwner.delete(ev.code);
  entries.get(id)?.key(ev, false);
}

export const hub = {
  register(id: string, entry: Entry) {
    entries.set(id, entry);
    if (!installed && typeof window !== "undefined") {
      installed = true;
      window.addEventListener("keydown", onDown);
      window.addEventListener("keyup", onUp);
    }
    return () => {
      entries.delete(id);
      if (touched === id) touched = null;
    };
  },
  touch(id: string) {
    touched = id;
  },
};
