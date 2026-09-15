# Conversation history

Glyf was built in chat sessions between Arpit and an AI coding assistant. This folder keeps that conversation, so the context behind every change survives.

## Files

| File | Contents |
|---|---|
| `messages-from-arpit.md` | Every message Arpit sent (117 as of 16 Sep 2026, 02:40), numbered, word for word, with date and time. Messages he sent while the assistant was still working on something are marked "(sent mid-task)". Screenshots and videos he attached are noted as "[screenshot attached]" or by file path |
| `transcript-YYYY-MM-DD.md` | One file per day: Arpit's messages and the assistant's written replies, in order. Tool calls, command output and file contents are left out; what they produced is in the code and the other docs |
| `context-snapshots.md` | Seven long summaries the assistant wrote when the conversation got too long to hold at once (12 Sep 13:16, 13 Sep 02:48, 14 Sep 13:55, 14 Sep 20:17, 15 Sep 00:28, 15 Sep 15:25, 15 Sep 23:55). Each lists the requests so far, the technical state, files changed, errors and fixes, and what was next. This is the most detailed technical record of how the project got where it is |

## Sessions

| Session | When (IST) | What |
|---|---|---|
| A | Fri 11 Sep 18:56 to Tue 15 Sep about 15:30 | Spec, M0 to M7 cores, redesigns, Android port, first website versions, search suite, gestures, Acti parity, autocorrect, dictionary, AI model research, website v7 |
| B | Tue 15 Sep to now | Continuation of A: website v8 (guided iMessage chats), waitlist, private GitHub repo, Vercel setup notes, mobile hero, these docs |
| C | Sat 12 Sep 20:29 to 21:05 | App Store capabilities question and archive signing errors |

Sessions A and B share their start, so their overlapping messages appear once.

## How these files were made

They were exported from the local chat logs. While exporting:
- API keys, the database connection string, the Privy app secret and app id, and a machine hostname were replaced with `[REDACTED...]` markers.
- Headings inside the assistant's replies were turned into bold lines so each day's outline stays readable.
- Local file paths to the assistant's scratch folders were shortened to `<scratchpad>` and `<assistant memory>`.
- The AI tool's product name is replaced with `[the assistant]` everywhere, including Arpit's messages, per his request to keep it out of the repo.
- The assistant's own text follows the no em dash rule. Apart from the redactions and that name, Arpit's messages are unedited.

To refresh them later, re-export from the chat logs with the same redaction, or append new messages by hand.
