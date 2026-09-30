# Temp mail — shared rules

Both keyboards read mail the same way (Swift `Engine/TempMail.swift`, Kotlin
`ime/TempMail.kt`), held to `cases.json`. Change a rule here, change it in both
and re-run both suites.

## Provider: mail.tm, called by the phone itself

Free, keyless (https://docs.mail.tm). Chosen 2026-09-30 when Arpit asked for a
free API ("i said to fucking find free temp mail apis"); Temp-Mail.io, first
picked, needs a paid premium plan. mail.tm's terms: **no proxying its API under
another domain** (so Glyf's server never sits between: each phone calls
`https://api.mail.tm` directly), **link back to mail.tm somewhere visible** (the
panel's "via mail.tm"), no reselling the API as a product, no illegal use.
Limit: 8 requests a second per IP, which one phone never nears. Mail never
passes through Glyf's server.

Send `Accept: application/json` (plain arrays, not JSON-LD) and
`Content-Type: application/json`.

| Step | Call |
|---|---|
| Domains | `GET /domains` → `[{id, domain, isActive, isPrivate}]`; take a random active, non-private one |
| Address | `POST /accounts {address, password}` → `201 {id, address}`; 422 = taken, try another name (up to 3) |
| Token | `POST /token {address, password}` → `{token, id}` (JWT; `id` is the account id) |
| Inbox | `GET /messages?page=1` with `Authorization: Bearer <token>` → `[{id, from:{address,name}, subject, intro, seen, createdAt}]`, newest first |
| One mail | `GET /messages/{id}` → adds `text` (string) and `html` (array of strings) |
| Delete | `DELETE /accounts/{id}` → 204 |

- Address: a lowercase word + 6 hex characters + `@` + domain (`maple3f9a2c@uberip.com`). Password: 20 random characters, kept only on the phone.
- A 401 re-takes the token once with the stored password, then retries; a second 401 ends the address.
- A 429 or a network error skips that check; three in a row pause checking for 60 s.
- Fetch a mail's body once (`GET /messages/{id}`) when it first appears, and keep it in memory only.
- Tests point the keyboard at a stand-in with the setting `tempMailBase` (default `https://api.mail.tm`): `qa/fake-mailtm.mjs` on port 8798.

## Reading a mail

**Sender:** `from.name` if not empty, else `from.address`.

**Text:** `text` if not blank, else the `html` parts joined and turned into text:
remove `<script>`, `<style>`, `<head>` blocks; `<br>` and the ends of
`p div tr li h1-h6` become new lines; other tags become a space; decode
`&amp; &lt; &gt; &quot; &apos; &nbsp; &#39;` and numeric entities; collapse runs of
spaces, trim the space around new lines, at most one blank line; trim. Keep the
first 4,000 characters.

**Code** (`extractCode(subject, text)`): scan `subject + "\n" + text` (first
6,000 characters) for candidates

    (?<![\w$€£₹.,/:-])((?:[A-Z]{1,3}-)?\d{3}[ -]?\d{3}|(?:[A-Z]{1,3}-)?\d{4,8})(?![\w%$€£₹/:]|[.,]\d)

- digits = the candidate without a leading `XX-` and without spaces or dashes; skip unless 4–8 digits;
- skip a bare 4-digit year 1900–2099 (a prefixed one like `G-2024` stays);
- score: +3 if it starts inside the subject; +3 if the 80 characters before it through 40 after hold a code word
  `\b(codes?|otp|passcode|pass code|pin|verification|verify|security|confirmation|confirm|one[- ]time|log ?in|sign[- ]?in|2fa|two[- ]factor|token|password)\b` (case-insensitive);
  +2 for exactly 6 digits, else +1; +1 for a letter prefix; −4 if the 30 characters before it hold
  `\b(phone|call|tel|order|invoice|ref|reference|account (?:number|no\.?|#)|zip|postal)\b`;
- keep the highest score ≥ 4 (the first on a tie); the code is the digits, or the prefixed form without spaces (`G-482913`).

**Link** (`extractLink(text, html)`): the first `https://` href of an `<a>` in the HTML whose
URL or link text matches `(verif|confirm|activat|validat|magic|log-?in|sign-?in|signin|auth|reset|token|onboard|welcome|join|invite)`
(case-insensitive; `&amp;` → `&`), else the first `https://` URL in the text matching it (trailing `.,;` dropped).
Nothing when none matches: never a logo or an unsubscribe link.
