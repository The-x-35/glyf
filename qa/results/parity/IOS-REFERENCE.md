# iOS keyboard: the reference for the Android parity pass

Arpit, 2026-09-30: "why the fuck does android ui for clipboard vault etc looks so shit i need you to work on matching android ui to ios now, i need it similar in everything as a brand identity it is". iOS is the reference; Android changes to match it.

Captured 2026-09-30 on the iPhone 17 Pro simulator (iOS 26.5, 402 × 874 pt, @3x). The build was the working tree at `a2d6ab1` plus the uncommitted mail.tm temp mail switch. No keyboard code was changed for these captures.

## The files

- **Names:** `ios-<surface>-light.png` and `ios-<surface>-dark.png` in this folder. That is 42 surfaces × 2 looks = 84 files.
- **Crop:** every file is 1206 × 1242 px, the same crop of a full 1206 × 2622 px screenshot: x 0–1206, y 1380–2622 px (402 pt wide, from y 460 pt to the bottom).
  - 1 pt = 3 px.
  - The tallest keyboard (the vault's edit strip) starts at y 471 pt, so every keyboard is fully in frame. What shows above it is the host's message field.
- **Host:** Messages, a new message to +1 555-564-8583. It follows the system look: light = system Light, dark = system Dark (`XCUIDevice.appearance`).
  - The keyboard follows the host.
  - Glyf's own app always stays light, so it can't host the dark set.
- **Not Glyf's:** iOS draws the keyboard's rounded sheet, its 16 pt band above the strip, and the globe and mic row under the keys.

## Seeded content (reproduce exactly)

Everything below was in place for both looks. The simulator was restored afterwards: App Group byte for byte from a backup, and calendar access granted again.

**Settings** (App Group `settings.json`; fresh-install values where they matter):

| key | value |
|---|---|
| `toolbarOrder` / `toolbarHidden` | `["search","clipboard","vault","dictation","translate"]` / `[]` (the default strip) |
| `bindings` | `{"v":"surface:vault","c":"connector:calendar"}` (a fresh install's two holds: purple dots on C and V) |
| `keyTheme` | `"site"`; `"glass"` only for the two `vault-glass` shots |
| `region` | `"US"` (no UPI kind; global product) |
| `translateOther` / `translateTarget` | `"Spanish"` / `"English"` |
| `lastLat`, `lastLon` | `37.7749`, `-122.4194` (San Francisco, for Maps) |
| `clipboardScreenshots` | `false` (Photos screenshots would join the clipboard's cards) |
| `candidates` `true`, `numberRow` `false`, `oneHanded` `"off"`, `themeBg` `""`, `translationHUD` `false` | defaults |
| `menuOrder` | removed (the default tile order) |
| `tempMailBase` | `http://127.0.0.1:8798` (`qa/fake-mailtm.mjs`) |

**Vault** (details in this order, then shorthand, then notes; start from an empty vault):

| kind | label | value |
|---|---|---|
| name | Name | Alex Rivera |
| email | Email | alex.rivera@example.com |
| phone | Phone | +1 415 555 0134 |
| address | Home | 123 Market St, San Francisco, CA 94103 |
| link | Website | alexrivera.dev |
| shorthand | `;sig` | Best, Alex |
| shorthand | `;omw` | On my way, see you in 10 |
| note | | Book club: Thursday 7pm at Maria's |
| note | | Gift ideas: headphones, a plant, the blue mug |

- **iOS route:** the details and shorthand went in through the keyboard's DEBUG vault tools (`adddetail`, `snippet` in `debug-vault.json`), and the notes as `notes.json`, newest first.
- **Android:** use its `seedvault`/`snippet` debug tools, or type them in the app.
- **After the clipboard shot:** the clipboard capture's **Save to vault** adds a third note ("Alex Rivera, 123 Market St, …"), but only after the vault shots.

**Clipboard history** (`clipboard.json`, newest first):

1. "See you at 6 by the north entrance". Copied 2 minutes ago.
2. "https://tryglyf.com/download". Copied 12 minutes ago; this is the link.
3. The long one: "Packing list:\n- Passport\n- Phone charger\n- Rain jacket\n- Snacks for the train\n- A book for the flight". Copied 50 minutes ago.
4. "Alex Rivera, 123 Market St, San Francisco, CA 94103". Copied 3 hours ago, **pinned**.

The system pasteboard was empty.

**Contacts search** (`contacts.json`; Apple's simulator sample contacts):
- Anna Haro: +1 555-522-8243, anna-haro@mac.com
- Daniel Higgins: +1 555-478-7672, d-higgins@mac.com
- Kate Bell: +1 555-564-8583, kate-bell@mac.com

For `search-contacts-off`, the file was removed.

**Calendar** (the app's `--glyf-seed-calendar`, with the phone's calendar access switched off so the keyboard reads the app's copy; the calendar colours are as seeded):
- **Today:** "Standup", 10:00–10:30, colour `#34C759`; "Design review", 15:00–16:00, location "Studio", colour `#7C5CFF`.
- **Tomorrow:** "Dinner with Zoya", 20:00–22:00, colour `#FF9500`.

**Recents:**
- Search: web "coffee", "weather tomorrow", "best pizza nearby"; maps "coffee near me".
- Emoji, frequently used: 😂 🍕 ❤️ 👍 🙏 😊 🔥 🎉 😍.
- Emoticons: `:-)`.
- No learned words: typing memory cleared.

**My glyfs** also lists "Say No Politely", a glyf built in the Glyf app (Build your own) and on no key. On Android, build any glyf with that name.

**Live content that will differ from run to run:**
- the search, Maps and hold-space answers (real models and search);
- KLIPY's trending GIFs and stickers;
- temp mail addresses (a random word + 6 hex).

## Shared tokens (`Design/GlassTokens.swift`)

The font is the **system font (SF Pro)** everywhere in the keyboard; there are no custom faces. On Android use Inter (the app's face) at the same numbers: 1 pt = 1 dp, and sizes in pt = sp. Weights: regular 400, medium 500, semibold 600, bold 700.

| token | light | dark | used for |
|---|---|---|---|
| system sheet (drawn by iOS, measured) | `#E2E4E8` | `#1B1B1D` | behind everything; panels are see-through to it |
| `keyColor` / `surfaceCard` | `#FFFFFF` | `#404041` | keys, and every card (tiles, vault cards, clips, rows, results) |
| key ink | `#000000` | `#FFFFFF` | glyphs on keys |
| `textPrimary` | `#121212` (white 0.07) | `#FFFFFF` | titles, values, row text |
| `textSecondary` | `#6B6B6B` (white 0.42) | `#A1A1A1` (white 0.63) | captions, labels, placeholders, times |
| `fillField` | `#EDF0F5` | `#2B2B2E` | secondary buttons (Copy), chips' icon squares, code pills |
| `fillSoft` | white 60 % (`#99FFFFFF`) | white 8 % (`#14FFFFFF`) | search tab track, Ask bar ✕, date/time pills |
| `scrim` | white 62 % (`#9EFFFFFF`) | black 55 % (`#8C000000`) | behind menus |
| `strokeHairline` | black 8 % (`#14000000`) | white 10 % (`#1AFFFFFF`) | card borders, strip dividers, suggestion slot lines |
| `strokeSeparator` | black 16 % (`#29000000`) | white 14 % (`#24FFFFFF`) | row separators in lists |
| `strokeFocus` | `#7C5CFF` @ 60 % | same | focused text field border |
| `accentPrimary` | `#7C5CFF` | `#7C5CFF` | primary buttons, the + button, bound-key dots, caret, g-key dot |
| `chipAccent` | `#8A6CFF` | `#C3B4FF` | purple words and marks on chips ("Insert", "Watch again") |
| `brandInk` / `GlyfMark.ink` | `#121212` / `#17181C` | same | selected clipboard filter, search go button, g key (dark) |
| `controlOn` (switch on) | `#17181C` | `#DBDBDB` | settings switches |
| `imBlue` | `#0A84FF` | `#0A84FF` | translate's Replace |
| `returnBlue` | `#007AFF` | `#0A84FF` | return key on go/search/send fields |
| `accentDanger` | `#F04438` | `#F04438` | status errors, delete marks |
| `fillKeyBound` (glass look only) | `#F6F4FF` | `#5C577A` | |

**Radii and shape:**
- Keys: 9.5.
- Cards: 12 in most panels. Exceptions: menu tiles 14, search results 15, games 16, the act panel's text 15 and version rows 14.
- Every corner is continuous (iOS `cornerCurve = .continuous`, a squircle). On Android, use a smooth-corner shape if one exists; otherwise the plain radius.

**Lines:** hairlines are 0.5 pt (list separators, game cards). Text fields and search result cards have a 1 pt border.

**Shadows:** none on keys or cards in the default look. The vault's + option pills: black 12 %, blur 8, y 2. The clipboard hold menu: black 14 %, blur 14, y 4.

**Toast** (`Surfaces/KeyboardToast.swift`), see `toast`:
- A pill 28 pt tall, corner 14, fill white 0.12 @ 94 % (`#F01F1F1F`).
- Text 13 semibold white; its width is the text (padded with two spaces each side) plus 12 pt.
- Centred 8 pt below the top of whatever it shows over.
- Fades in 0.15 s, holds 1.9 s, fades out 0.3 s. It is the same in both looks.

## Keyboard geometry (every surface)

Code: `Layout/KeyboardView.swift`, `Layout/KeyView.swift`, `Design/GlassTokens.swift` (`KeyMetrics`).

- **Heights:** the strip's content box is 44 pt (`stripContent`); iOS 26 adds its own 16 pt band above it. The keys take 4 rows × 54 pt = 216 pt on a 402 pt phone (56 pt rows at 414 pt and wider).
- **Key size:** 43 pt tall, with an 11 pt gap between rows. Side margin 6.5, gap between keys 6. A letter is (width − 13 − 54) / 10 = 33.5 pt wide at 402. Shift, delete and the third-row mode key are 1.35 letters wide.
- **Glyphs:**
  - lowercase letters 24.5 regular, capitals 22 regular;
  - "123"/"ABC" 18, "#+=" 13;
  - shift, delete, globe and emoji are SF Symbols 19.5 light;
  - the space bar carries "glyf" at 15 regular in key ink @ 40 % (a watermark);
  - return is an SF Symbol, or a word at 16.
- **Bound key:** a purple dot (`#7C5CFF`), 5 × 5 pt, 5.5 pt in from the key's top and right edges.
- **Flat keys:** no shadow and no border.
- **Press balloon:** radius 12, letter at 34.
- **Heights with a surface:** panels take the keys' place and the keyboard keeps its height (260 pt + iOS's band). The exceptions add height:

  | surface | adds |
  |---|---|
  | emoji board | +44 pt |
  | Ask bar | +44 pt (its chips row) |
  | search | +40 pt |
  | vault edit strip | +52 pt (a 96 pt strip in place of the 44 pt one) |

## The surfaces

### 1. Strip at rest, and word suggestions

- **Files:** `strip-rest`; `strip-suggestions` (after typing "hel").
- **Drawn in:** `Surfaces/Toolbar.swift` (`GlyfToolbar`); g key `Design/GlyfMark.swift`.
- **The g key:**
  - 41 × 30 pt, corner 10, with its ink 19 pt from the left edge (16 pt margin + 3 pt).
  - Light: white face, "g" `#17181C`, purple dot.
  - Dark: face `#17181C` with a 1 pt ring of white 16 %, a white "g" and the purple dot.
- **Tools:**
  - SF Symbols 21 pt regular, tinted textPrimary @ 78 %: `magnifyingglass`, `doc.on.clipboard`, `person.text.rectangle` (vault), `mic`, `translate`.
  - Spread evenly from the g key to 16 pt from the right edge.
  - Each has a 12 pt tap margin a side and a corner-10 press area.
  - The default look has no divider after the g key.
- **Suggestions:**
  - The g key stays; three equal slots follow.
  - Words at 17 regular; a correction is 17 semibold; a word kept as typed shows in quotes in textSecondary.
  - 1 pt `strokeHairline` lines between the slots, 56 % of the strip's height.
- **Strip chip:** 38 pt tall, from `strip:smart`. Not in this set: see S215/S217 in `qa/results`.

### 2. Keys: number and symbols pages

- **Files:** `keys-123`, `keys-symbols`.
- **Drawn in:** `Layout/KeyboardLayout.swift`, `Layout/KeyView.swift`.
- **Rows:**
  - `1 2 3 4 5 6 7 8 9 0` / `- / : ; ( ) $ & @ "` / `#+= . , ? ! ' ⌫` / `ABC ☺ space return`.
  - Symbols: `[ ] { } # % ^ * + =` / `_ \ | ~ < > € £ ¥ •` / `123 . , ? ! ' ⌫`.
  - The strip keeps its tools.

### 3. The g menu

- **Files:** `gmenu` (opened); `gmenu-end` (scrolled to the last row).
- **Drawn in:** `Surfaces/GlyfShell.swift` (`buildGrid`, `layoutGrid`); icons `GlyfToolbar.icons`.
- **Panel header, in the strip, the same for every panel:**
  - ✕ (SF `xmark` 21 regular, textPrimary) in the g key's place.
  - Then ‹ (`chevron.left` 15 semibold), when there is somewhere to go back to.
  - Then an optional panel icon (SF 17 medium).
  - Then the title (15 semibold, textPrimary).
  - An optional action at the right edge (SF 16 semibold, e.g. the act panel's retry).
  - With the menu open, the strip keeps its tools beside the ✕.
- **Grid:**
  - 4 columns, 6 pt side inset, 8 pt gaps.
  - A tile is `max(64, (panel height − 48) / 2)` tall: two rows show, with the third peeking in.
  - Tiles are surfaceCard, corner 14, flat; the glass look adds a 1 pt hairline border.
  - The icon is an SF Symbol 22 regular in textPrimary: `wand.and.stars` Rewrite, `calendar` Calendar, `envelope` Temp mail, `play.square.stack` GIFs, `sparkles` Ask Glyf, `square.grid.2x2` My glyfs, `creditcard` Pay, `gamecontroller` Games, `gearshape` Settings.
  - The label is 12 medium textPrimary, centred.
  - Icon (26 tall) + 8 + label (15 tall), centred in the tile.
- **Tiles:** the menu shows only the tools not on the strip, in the order Rewrite, Calendar, Temp mail, GIFs / Ask Glyf, My glyfs, Pay, Games / Settings.

### 4. Clipboard

- **Files:**
  - `clipboard` (pinned on top, RECENT starting);
  - `clipboard-recent` (scrolled to the recent cards);
  - `clipboard-menu` (the pinned card held);
  - `toast` (its **Save to vault**, showing "Saved to vault").
- **Drawn in:** `Surfaces/ClipboardPanel.swift`.
- **Own header, 52 pt; the strip is hidden:**
  - Back: a 38 pt surfaceCard circle with `arrow.left` 18 medium.
  - Title "Clipboard" 22 medium, textPrimary, 14 pt after the back button.
  - Edit: a 38 pt circle with `pencil` 17 medium.
- **Filters row, 34 pt:**
  - Pills 26 pt tall, corner 13, 7 pt apart, from 12 pt in.
  - Each: an SF icon 11 semibold (`line.3.horizontal`, `textformat`, `link`, `photo`) + a title 13.5 medium: All, Text, Link, Image.
  - Selected: brandInk `#121212` fill with white. Others: surfaceCard with textPrimary.
- **Sections:** "PINNED" and "RECENT", 12.5 medium, textSecondary, tracking 0.6, rows 30 pt.
- **Cards:**
  - Two-column masonry (as Gboard), 12 pt side inset, 10 pt gaps.
  - surfaceCard, corner 12, 14 pt padding.
  - Text 15 regular textPrimary, at most 4 lines.
- **Hold menu:**
  - The held card stays lifted over a scrim.
  - The menu box is 176 pt wide, surfaceCard, corner 14, with a shadow.
  - Rows are 50 pt: an SF icon + a title 16 regular (Paste `doc.on.clipboard`, Save to vault `person.text.rectangle`, Pin/Unpin `pin`/`pin.slash`, Delete `trash`), with hairline separators.
  - It sits beside the card, or below it when there is no room.

### 5. Vault

- **Drawn in:** `Surfaces/GlyfShell.swift` (the `vault` and `vault:detail` screens: `buildVaultGrid`, `layoutVaultGrid`, the + in `buildAddButton`/`layoutAddButton`); edit strip `Surfaces/NoteEditSurface.swift` + `Surfaces/InlineEditor.swift`; the list look is `ShellCell` in `GlyfShell.swift`.
- **Files:** `vault`, `vault-add`, `vault-newdetail`, `vault-edit-note`, `vault-edit-email`, `vault-edit-shorthand`, `vault-glass`, `vault-glass-newdetail`.
- **Header:** ✕ ‹ Vault (the strip header, section 3).
- **Card grid:**
  - 3 columns, 6 pt side inset, 6 pt gaps.
  - Cards are (panel height − 12) / 3 tall: three rows fill the panel and it scrolls on.
  - surfaceCard, corner 12, flat.
  - Label on top: 11 semibold, textSecondary, UPPERCASE, tracking 0.44. Shorthand shows its trigger as typed (`;sig`), and notes read "NOTE".
  - Value under it: 13 medium, textPrimary, one line, truncated at the end.
  - 8 pt text inset; the label + 2 + value block is centred vertically.
  - Order: details, shorthand, notes, images.
- **The + (`vault-add` open):**
  - A 46 pt circle, 12 pt from the panel's right and bottom, accentPrimary fill, white `plus` 20 semibold. Open, it turns an eighth of a turn into ×.
  - Its options stack above it, right-aligned: three pills, up to 36 pt tall (28 minimum), 6 pt apart, same width.
  - Each pill: surfaceCard, fully round, with a shadow; a mark 14 semibold in accentPrimary (`note.text`, `person.text.rectangle`, `bolt`) + a title 15 medium: "New note", "New detail", "New shorthand".
- **New detail (`vault-newdetail`):**
  - The same 3-column cards, one per kind: an SF 18 regular icon over the name (13 medium, centred).
  - Kinds: Name `person`, Email `at`, Phone `phone`, Address `house`, Wallet address `wallet.bifold`, Link `link`, Other `tag`.
  - UPI `indianrupeesign` shows only when the region is IN.
- **Edit strip (`vault-edit-*`):**
  - A 96 pt strip in place of the tools; the keys stay live.
  - ✕ at the left (`xmark` 13 semibold, textSecondary).
  - Field: 34 pt tall, corner 12, surfaceCard with a 1 pt hairline border (60 % purple while focused), text 15 regular, placeholder textSecondary, a 2 pt purple caret.
  - Save: a pill 62 × 30, corner 15, textPrimary fill, 14 bold; white text in light, `#121212` in dark.
  - A status line 12 regular in accentDanger under the field.
  - Placeholders: note "Write a note…"; detail (Email) "Email" with a leading `at` icon (SF 14 semibold, accentPrimary); shorthand two fields, "Shortcut" (starts filled with ";"; at most 112 pt, 36 % of the width) and "Types out".
- **Glass look (`vault-glass*`, setting `keyTheme` = "glass"):**
  - A list, not cards: a 36 pt header row inside the panel (‹, the title 15 semibold centred, ✕).
  - Two-line rows 52 pt: a chip icon 28 pt, corner 7, fillField; the title (15 regular, textPrimary, top at 8 pt) with the value under it (textSecondary, top at 28 pt).
  - "Open in Glyf app ↗" underneath, 13 medium.
  - The + as in the default look.

### 6. My glyfs

- **File:** `myglyfs`.
- **Drawn in:** `Surfaces/GlyfShell.swift` (the `glyfs` screen, `ShellCell`).
- **Header:** ✕ ‹ My glyfs.
- **Grouped list rows (as iOS Settings):**
  - Rows 44 pt.
  - The group card: 12 pt side inset, surfaceCard, corner 12 on the group's first and last rows only.
  - 16 pt text inset.
  - A chip 28 × 28, corner 7, fillField, holding an SF 14 medium icon (or a letter 14 bold).
  - Title 15 regular textPrimary; detail 15 regular textSecondary on the right ("Hold C").
  - Chevron 14 × 20 in textSecondary @ 55 %.
  - Separators 0.5 pt strokeSeparator, from the text's x to the edge.
- **Rows:** Calendar (Hold C), Vault (Hold V), Say No Politely, then Build your own (+).

### 7. Calendar

- **Files:** `calendar` (its first view: today, with the 2 seeded events), `calendar-month`, `calendar-newevent`.
- **Drawn in:** `Surfaces/CalendarSurface.swift`; New Event `Surfaces/EventComposer.swift`.
- **Header:** ✕ plus the `calendar` icon and "Calendar" in the strip.
- **Day header row (32 pt, 12 pt insets):**
  - Date "Wed, Sep 30", 15 semibold.
  - ‹ › `chevron.left/right` 13 semibold.
  - A "Month" pill: surfaceCard, 13 semibold, 76 × 30, corner 15; it reads "Done" at 66 wide in the month grid.
  - A video (call) button and a + button: 30 pt surfaceCard circles, `video` 13 semibold and `plus` 15 semibold.
- **Event rows:**
  - surfaceCard, corner 12.
  - A colour bar 4 pt wide, corner 2, in the event's colour.
  - Start 14 semibold ("All day" 13), end 12 regular textSecondary under it.
  - Title 15 semibold; location 12.5 textSecondary under it.
- **Actions row:**
  - 38 pt pills, 13 semibold, 8 pt apart: "Insert date" (surfaceCard), "Share free time" (accentPrimary, white), "Book a time" (surfaceCard).
- **Month grid:**
  - Weekday letters 11 semibold, textSecondary.
  - Days 15 regular; today and the selected day are semibold, and the selected day sits in an accentPrimary circle with white text.
  - Event dots 4 pt.
- **New Event:**
  - A header with "Cancel" 16 regular accent, "New Event" 16 semibold, and "Add" 16 semibold (grey until a title).
  - A surfaceCard card, corner 12, with rows Title / Starts / Ends at 15 regular, separated by strokeSeparator.
  - Date and time pills: fillSoft, corner 7, 15 regular.
  - The note under it is 13 regular textSecondary.

### 8. Search

- **Files:**
  - `search` (the Search tab's landing);
  - `search-results` ("coffee"; this run's web answer was one answer card);
  - `search-maps` (Maps, "coffee": three places);
  - `search-contacts-empty` (the Contacts tab as it opens);
  - `search-contacts` ("a" typed: the matches as chips);
  - `search-contacts-off` (no contacts.json).
- **Drawn in:** `Surfaces/SearchSurface.swift`.
- **Header row, 44 pt:**
  - ✕ `xmark` 13 semibold, textSecondary, at the left.
  - A tab track: fillSoft, fully round, 36 pt tall, 3 pt padding, 2 pt gaps, holding tabs 35 × 30. Each tab is an SF 15 medium icon: `magnifyingglass`, `play.rectangle`, `map`, `person.crop.circle`, `character.bubble`. The selected tab has a surfaceCard thumb.
  - The query field: 34 pt, corner 12, surfaceCard, 1 pt hairline border (60 % purple when focused), text 15, placeholder "Search…".
  - The go button: `arrow.forward.circle.fill` 34 pt in brandInk.
  - After results, an "ABC" text button (14 semibold) brings the keys back.
- **Chips row under it (40 pt):**
  - Pills 30 pt tall, fully round, 8 pt apart, from 12 pt in: an SF 11 semibold icon (`clock` for a recent) + a title 13.5 medium.
- **Result cards:**
  - surfaceCard, corner 15, 1 pt hairline border, inset 10 pt a side and 4 pt top and bottom.
  - Answer card: a value 34 bold (22 when long) and a line 12.5 textSecondary.
  - Link card: a favicon chip, corner 10, the title 14.5 medium, the detail 12.5.
  - Video: a thumbnail, corner 9; a badge 10 semibold, corner 4; the title 14 medium, the channel 12.5.
  - Place: a map thumbnail, corner 9; the name 14.5 medium; the distance and meta 12.5.
  - Maps from OpenStreetMap carry the credit line "Maps © OpenStreetMap contributors · Geoapify", 11 regular.
- **Contacts matches:** chips with `phone` or `envelope`, reading "Anna Haro · +1 555-522-8…".
- **Known iOS bug, found during this capture:** the status line (12.5 regular, textSecondary, in the chips row) is laid out but never given its text; `SearchSurface` never sets `statusLabel.text`.
  - So "Type a name", "Turn on Contacts search in the Glyf app", "Searching…" and "Nothing found" never show.
  - That is why `search-contacts-empty` and `search-contacts-off` look the same. Android should show the line.

### 9. Translate bar

- **File:** `translate` ("hola nos vemos en la oficina" typed, so the translation shows).
- **Drawn in:** `Surfaces/TranslationHUD.swift`.
- **Layout:** it takes the strip's place; the keys stay.
  - A direction pill at 8 pt: surfaceCard, 30 pt, fully round, 13 semibold, "Spanish → English".
  - The translation: 17 semibold textPrimary, one line, scrolled to its end.
  - "Replace": an imBlue pill 84 × 30, white 14 semibold.
  - ✕ `xmark` 13 semibold, textSecondary, at the right.

### 10. Hold space

- **Files:**
  - `holdspace-ask` (the Ask bar on an empty field);
  - `holdspace-rewrite` ("ya ok will send deck b4 6": the versions);
  - `holdspace-answer` ("who is the ceo of tesla");
  - `holdspace-places` ("coffee near me").
- **Drawn in:** Ask bar `Surfaces/GlyfBar.swift`; the rest `Surfaces/ActSurface.swift`.
- **Ask bar, in the strip:**
  - ✕ in a fillSoft rounded square, corner 10, `xmark` 15 semibold.
  - A prompt field: surfaceCard with a 1 pt hairline border, fully round (corner = half its height), a leading `sparkles` icon (SF 14 semibold, accentPrimary), placeholder "Ask Glyf", text 15.
  - A round run button (`arrow.up` 12 bold): textPrimary fill when there is something to send, else fillField.
  - A 44 pt chips row under it: chips 32 pt, surfaceCard, corner 16, 13.5 semibold. The copied-text chip has an 11 semibold icon and a 9 bold ✕, text 13.
- **Act panel:**
  - The strip header reads ✕ plus `sparkles` "Glyf", with a retry (`arrow.clockwise`) at the right.
  - Answer text: a surfaceCard box, corner 15, text 15.5 regular.
  - Buttons: 38 pt, corner 19, 15 semibold. "Copy" is surfaceCard with textPrimary. "Insert ↑" is a textPrimary fill (inverse text) with `arrow.up` 12 bold after the word.
- **Versions:**
  - Rows: surfaceCard, corner 14, inset 10 pt a side and 4 pt top and bottom.
  - The version name is 13 semibold textSecondary, in a 92 pt column: Basic, Professional, Polite, Shorter, …
  - The text is 15 regular textPrimary, at most 3 lines.
- **Places:** the Search place card, with Copy and Insert under it.
- **While working (not captured):** a brandInk rounded square, corner 13, with a white "g" 27 bold and a purple dot; "Working…" 15 semibold; the intent 14 medium, textSecondary.

### 11. Emoji board

- **Files:** `emoji` (Emoji tab), `emoji-gifs` (GIFs → Trending), `emoji-stickers`.
- **Drawn in:** `Surfaces/EmojiBoard.swift`; the GIF/sticker grids `Surfaces/MediaGrid.swift`.
- **Height:** 44 pt taller than the letters, as Apple's is.
- **Top row:**
  - A search field, corner 12, no border, filled white @ 48 % (light) / white @ 10 % (dark), a leading `magnifyingglass` (SF 15 medium, textSecondary) and text 17: "Search Emoji", or "Search KLIPY" for GIFs and stickers.
  - The mode tabs: Emoji (`face.smiling` 17 regular), Stickers, GIF (boxed "GIF" 10.5 heavy), ":-)" (14 semibold).
  - The selected tab is textPrimary on a round thumb; the others are textSecondary.
- **Section labels:** 12 semibold grey ("FREQUENTLY USED", "TRENDING"). "Powered by KLIPY" is 11 medium at the right.
- **Grid:** cells 47 × 39 pt, emoji at 32. GIFs are a 2-column masonry, stickers 4 columns.
- **Bottom bar:**
  - "ABC" 15 regular, the category icons (SF 16 light), delete (SF 18 regular).
  - For GIFs, a chips row instead: Trending / Haha / Love / Sad at 16; the first is semibold, and the selected one is on a pill.

### 12. Games

- **File:** `games`.
- **Drawn in:** `Surfaces/GamesSurface.swift`.
- **Header:** ✕ plus `gamecontroller` "Games".
- **Picker:**
  - Two cards, inset 12 pt: surfaceCard, corner 16, 0.5 pt hairline border.
  - Art 52 pt tall; 10 pt; the name 17 semibold; "New" or "Best 12" 13 regular (monospaced digits), textSecondary. The block is centred.

### 13. Settings, in the keyboard

- **Files:** `settings` (top), `settings-end` (scrolled to the bottom).
- **Drawn in:** `Surfaces/GlyfShell.swift` (the `settings` screen, `ShellCell`).
- **Header:** ✕ ‹ Settings.
- **List:**
  - The grouped list of section 6.
  - Section headers are UPPERCASE 13 regular, textSecondary, tracking 0.4: TYPING, FEEL, MORE.
  - Rows 44 pt with a switch (iOS `UISwitch`, on colour controlOn) or a chevron.
  - Rows: Autocorrect, Correct automatically, Suggestions, Auto-capitalize, Double-space for period, Number row, One-handed / Sound on keypress, Haptic feedback on keypress / Paste title with link, Toolbar items (chip `slider.horizontal.3`).

### 14. Temp mail

- **Files:** `tempmail-empty`, `tempmail-inbox` (one mail: "Acme", "Your Acme code", code 482913), `tempmail-mail` (opened).
- **Drawn in:** `Surfaces/TempMailView.swift`.
- **Header:** ✕ ‹ Temp mail.
- **Empty:** "Create address", a 200 × 44 accentPrimary pill with white 14 semibold, centred.
- **Address card:**
  - surfaceCard, corner 12, 82 tall, 12 pt insets.
  - The address is 15 medium on its own line, with its middle cut when long.
  - Under it: "Insert" (accentPrimary, white 14 semibold, at least 84 × 32, fully round) and "Copy" (fillField, textPrimary 14 semibold, at least 72 × 32).
  - At the far end: "New" and "Delete" as 13 medium textSecondary text.
- **Watch line:** "Watching · 14:52 left" 12 regular textSecondary; "Stopped ·" is followed by "Watch again" 12 semibold chipAccent.
- **Inbox rows:**
  - 52 pt, surfaceCard, corner 12, 6 pt apart.
  - The sender 14 bold, the time 12 textSecondary on the right, the subject 13 textSecondary.
  - The code pill: fillField, 22 pt, corner 11, with the code 13 semibold (monospaced digits) and "Insert" 13 semibold chipAccent.
  - With no mail: "No mail yet", 14 textSecondary, centred.
- **Open mail:**
  - The subject 16 semibold; "Acme · now" 12 textSecondary.
  - The code card: surfaceCard, corner 12, 56 tall. The code is 28 semibold, monospaced digits, tracking 2. Copy (fillField) and Insert (accentPrimary) are 34 pt pills.
  - "Insert link": a fillField pill, 32 tall, 14 semibold.
  - The text is 14 regular.
- **Credit:** "via mail.tm" 11 regular textSecondary, centred in a 20 pt row at the foot of every Temp mail screen. mail.tm's terms require it.

## Found while capturing (for the lead)

1. **Search status line:** `SearchSurface` never draws its status line (section 8). This is an iOS bug and needs a code fix; this pass made no code changes.
2. **Dark clipboard filter:** the selected filter pill is brandInk `#121212` on a `#1B1B1D` sheet, so "All" reads as bare white text with no visible pill (`clipboard-dark`). Android copying it exactly will copy that.
