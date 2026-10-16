# Keyboard themes

Keyboard themes on both keyboards (iPhone and Android). Arpit, 2026-10-17: "make themes, v cool themes for keyboard, we can have like vintage and like a typewriter theme, and like themes for figures like spiderman maybe, research which character we can use and make for them. i need as many as you can make but i need them to be super classy and cool and sexy and useful, and make sure not to touch the dimensions".

Status: **built on both keyboards, second design pass (17 Oct 2026).** The first pass (24 themes, below in §1 to §5 and §8 to §10 for its research and plumbing) was rejected on sight. Arpit: "what shit have u made, v bad aesthetically, some are maybe good, i need you to research designs learn and then make properly". The palettes now come from `shared/themes/design.py`, which writes `shared/themes/themes.json`; never edit the JSON by hand. The first pass's §6, §7 and §11 (per-theme colours, contrast tables and the JSON copy) are gone because they described the rejected palettes.

## Second pass: how the themes are designed

What was wrong with pass one, from its screenshots on the iPhone:
- a coloured outline on every key (Gatsby, Terminal, Synthwave), which reads cheap;
- dark key slabs on Apple's light sheet (Typewriter, Primary), forced by a rule that every key stand 3:1 off the sheet;
- dark modes that flipped to cream keys;
- too many saturated colours at once.

What the best keycap sets do (GMK 9009, Olivia, Godspeed, Botanical, Laser, Red Samurai; GMK's own plastic codes, e.g. L9 #D8D2C3, U9 #ACA693, CR #171718, 3C #C87E74), and so what every theme now does:
1. **Three tiers only.** Letters (the space bar matches them), the function keys one quiet step away, and **one accent, on return**. With a theme, return always wears it (iOS `KeyView.isPrimaryReturn`, Android `skinClass`), the way a keycap set colours its enter key.
2. **Legends in a dark, low-chroma ink** on light keys, or a tinted cream on dark ones. No neon legends except where the object glows (Terminal, Midnight Drive). **No outlines.**
3. **Keys belong on the sheet iOS draws.** Light letters are lighter than Apple's light sheet (#E2E4E8); in dark mode function keys sit at least 1.3:1 above the dark sheet (#1B1B1D) and letters at least 1.6:1, Apple's layering (design.py `lift`).
4. **Apple's edge, not a frame:** a hard 1pt bottom shadow (28% light, 55% dark).
5. **The callout is the key** it grows from (Apple's), never a new colour.
6. **Special faces only where the object has one:** Courier Prime (Typewriter), JetBrains Mono (Terminal), Libre Caslon (221B), IM Fell (Wonderland), Marcellus (Gatsby). Everything else is the system face, at today's sizes.
7. **No textures.** The Android board is the letter key's own tint a step down (light: 11% darker; dark: 62% into black), never the function keys' colour. A yellow or blue board turned whole keyboards into a slab.
8. Contrast (`shared/themes/check_contrast.py`, both keyboards' tests): text 4.5:1, the bound-key dot 3:1, keys against board and sheet 1.15:1 (Apple's own light keys are 1.27:1). The old 3:1 key rule is what produced the slabs.

Checked by screenshots of the real keyboards, every theme in light and dark, on the iPhone 17 Pro Max simulator and the Android emulator; key rectangles unchanged.

### The 29 themes

| Theme | Group | Face | Mood |
|---|---|---|---|
| Typewriter | Objects | Courier Prime | An Italian portable: ivory keys, warm grey shift, a Valentine-red return. |
| Beige Box | Objects | system | A 1984 desktop computer: putty letters, khaki function keys, a rose return. |
| Rangefinder | Objects | system | A film camera: satin chrome keys, a black leatherette return with a yellow legend. |
| Walnut | Objects | system | A writing desk: walnut function keys, brass on the return. |
| Carrara | Objects | system | Polished marble and a brass inlay. |
| Graphite | Objects | system | Machined aluminium and anodised black. |
| Terminal | Objects | JetBrains Mono | A green-screen terminal: phosphor letters, monospaced. |
| Primary | Objects | system | A Bauhaus poster: cream keys, a red shift, a blue delete, a yellow return. |
| Greenhouse | Nature | system | Sage leaves and a deep fern return. |
| Sakura | Nature | system | Blossom paper and plum ink. |
| Tide | Nature | system | Sea glass and deep water. |
| Sahara | Nature | system | Warm sand and a terracotta return. |
| Moss | Nature | system | Lichen and old gold. |
| Arctic | Nature | system | Snow, frost and polar night. |
| Lunar | Nature | system | A 1969 cockpit: cream switches, powder-blue panels, an orange abort. |
| Blush | Moods | system | Ivory and rose; black keys with rose legends at night. |
| Champagne | Moods | system | Porcelain and rose gold. |
| Midnight Drive | Moods | system | A coastal road at 2am: violet keys, cyan letters, a magenta return. |
| Noir | Moods | system | Black and white, and one red. |
| Rooftop | Moods | system | A city roof at night, under a sodium streetlight. |
| Overclock | Moods | system | Acid yellow function keys and a hot-pink return. |
| Orbit | Moods | system | A white hull and a mission-orange return. |
| Samurai | Moods | system | Washi paper, a vermilion seal, gold leaf; red lacquer keys at night. |
| 221B | Stories | Libre Caslon Text | A Victorian study by gaslight: tweed, Caslon type, an oxblood return. |
| Wonderland | Stories | IM Fell English | An 1865 engraving: cream paper, black ink, a playing-card red. |
| Emerald City | Stories | system | Jewel green and gold, as the 1900 book drew it. |
| Nautilus | Stories | system | Brass and verdigris, twenty thousand leagues down. |
| Gatsby | Stories | Marcellus | West Egg, 1925: ivory and champagne by day, black lacquer and gold by night. |
| Dracula | Stories | system | Candlelight, bone and oxblood. |

Contents: Second pass (the current design) · 0 Rules that never move · 1 Legal: which characters are safe · 2 How themes work today · 3 What a theme may change · 4 Platform limits · 5 Colour model (first pass; its 3:1 key rule is retired) · 8 Implementation · 9 Considered and cut · 10 Decisions for Arpit

---

## 0. Rules that never move

1. **No dimension changes.** A theme never touches these, on either keyboard:
   - Key geometry: `KeyMetrics` in `app/ios/GlyfKeyboard/Design/GlassTokens.swift`. Side margin 6.5, gaps 6 and 11, rows 54 and 56, keys 43 and 45, side keys 1.35×, plus the pads and sideways rows. Android uses the same numbers in `GlyfKeyboardView.kt`.
   - Radii: `radiusKey` 9.5, `radiusCard` 18, the 12pt balloon.
   - Strip: `stripContent` 45, `stripBand` 0, `stripLift` -1.5. The g pill stays 41×30.
   - Type sizes: every `.systemFont(ofSize:)` in `Layout/KeyView.swift` (letters 24.5 lowercase and 22 capitals, the rest as they are) and every `textSize` in Android's `drawFace` and `drawPadFace` (letters 22/20 dp). The strip's 17pt suggestions stay too.
   - Borders are drawn inside the key's bounds (`CALayer.borderWidth`, Android inset stroke), so a 1pt border makes no key bigger. The shadow edge falls in the 11pt gap below the key and doesn't move the key either.
2. **A different font keeps today's point size.** A typewriter face at 24.5pt looks a bit smaller or bigger than SF at 24.5pt. That is fine. Never compensate with size. If a face sits visibly off-centre, a vertical nudge of at most ±1pt is allowed. It moves the glyph, not the key. Measure it and record it per font.
3. **The iPhone keyboard paints no board.** iOS draws its own sheet behind every third-party keyboard, plus a bar below it (globe, mic) and sometimes a 16pt band above it, all in the host app's colours. A painted board left a slab inside that tray. That is why colour themes were retired on 2026-09-27 (commit af38458; Arpit: "the top bar cuts with themes and looks shit"). So on iOS a theme colours **keys, glyphs, the press popup, chips, the dot, shadows, borders, the font and the sound**, and keys sit on the system sheet. The board colour, board gradient and board texture are **Android-only** (and used in the app's previews). The iOS strip stays clear.
4. **The keyboard follows the host.** Every theme ships a light and a dark variant. iOS picks one from the host's appearance, as today. Android picks from its Appearance setting (auto, light or dark). No theme forces its hero mode on iOS. That forcing is what cut the old themes off.
5. **The brand stays.** The g pill (white in light, `#17181C` in dark, `GlyfMark`), the "glyf" watermark on the space bar (key ink at 40%) and the Insert chip's layout don't change. A theme only recolours the chip's face and accent.
6. **One feature, one place.** Themes replace nothing and add no new menu entry. They go in the app's Keyboard screen under **Look**, next to Glyf and Glass (`app/lib/profile/keyboard_screen.dart`).

---

## 1. Legal: which characters are safe

*This is research, not legal advice. Have an IP lawyer read §1.3 before the story themes ship (§10).*

### 1.1 Spider-Man, Batman, Marvel, DC: no

- **Copyright.** Visual characters with consistent, distinctive traits are protected on their own, apart from any one story. In *DC Comics v. Towle* (9th Cir. 2015), even the Batmobile was a protected "character" under a three-part test: physical and conceptual qualities, consistent identifiable traits, and unique expression. Spider-Man (1962) and Batman (1939) are both under copyright until the 2030s at the earliest. Every later costume and design carries its own term. [Towle](https://en.wikipedia.org/wiki/DC_Comics_v._Mark_Towle)
- **Trademark.** The names, logos and emblems (SPIDER-MAN, the spider chest emblem, the bat symbol) are registered marks, and Marvel and Disney enforce them against merchandise. For example, Marvel sued a Jerusalem shop over kippahs carrying the red-and-blue costume design. The theory was likelihood of confusion: buyers would think the goods came from Marvel. [Kippa Man](https://jweekly.com/2012/09/21/marvel-comics-suing-jerusalem-shop/) · [Disney/Marvel v. a theatre](https://www.law360.com/articles/647567)
- **Trade dress and look-alikes.** You can infringe without a name or logo. A red-and-blue palette with black web lines, a spider motif, wall-crawling skyline art, or a nickname like "web-slinger" or "Spidey" all call up the character. That is the confusion trademark law guards against, and it would be a copy of protected visual expression. An "inspired by" theme has to avoid all of it: the **name**, **logos and emblems**, the **costume's distinctive colour-and-pattern combination**, the **character's likeness or silhouette**, and its **catchphrases and nicknames**.
- **App Store.** Guideline 5.2.1 bars third-party trademarks and copyrighted works without permission. Reviewers ask for proof of rights. [5.2.1 rejections](https://developer.apple.com/forums/thread/114606)
- Side note: the joint DC and Marvel "SUPER HERO" registrations were cancelled by default in 2024 (the Superbabies petition). The word "superhero" is usable in a description, but that changes nothing above. [Womble Bond Dickinson](https://www.womblebonddickinson.com/us/insights/alerts/its-bird-its-plane-its-public-domain-uspto-cancels-marvel-and-dc-comics-trademarks)

**So: no Spider-Man, Batman, Marvel or DC theme, and no thin disguise of one.** The "Web Slinger" idea becomes **Rooftop** (§6, theme 20): an original city-at-night hero mood with no red-and-blue scheme, no web or spider, no bat and no emblem.

### 1.2 Public-domain characters: the status in 2026

US rule: works published in 1930 or earlier are in the public domain as of 1 January 2026 (95-year term). Only **that version** is free. Later stories, studio redesigns and film looks keep their own copyright. **Trademarks are separate and can last forever.** [Duke CSPD, Public Domain Day 2026](https://web.law.duke.edu/cspd/publicdomainday/2026/)

| Character | US status (2026) | Safe for a Glyf theme? | Use only | Trademark and other risks |
|---|---|---|---|---|
| **Sherlock Holmes** | All 60 Doyle stories public domain since 1 Jan 2023. *Klinger v. Conan Doyle Estate* (7th Cir. 2014) freed the characters. [Klinger](https://en.wikipedia.org/wiki/Klinger_v._Conan_Doyle_Estate,_Ltd.) | **Yes → "221B"** | Victorian study, gaslight, tweed, 221B Baker Street. Sidney Paget's 1890s illustrations are public domain too. | The Conan Doyle Estate litigates often. Don't use the BBC *Sherlock* or Downey films' looks, and don't call the theme "Sherlock" (the Estate's marks). "221B" is an address. |
| **Alice in Wonderland** | Carroll and Tenniel (1865, 1871): public domain. [Gutenberg, Tenniel](https://www-test.gutenberg.org/ebooks/114) | **Yes → "Wonderland"** | Tenniel's engraving style, playing cards, cross-hatching. | Disney's 1951 Alice (her blue dress and pinafore, the Disney Cheshire grin, its type) is still Disney's. Keep the engraving look. |
| **The Wizard of Oz (book)** | Baum and Denslow (1900): public domain. | **Yes → "Emerald City"** | Emerald greens, gold, Denslow's art-nouveau line, green spectacles. Note that in the book the shoes are **silver**. | The 1939 MGM film's elements (ruby slippers, Judy Garland's look, the film's Emerald City) are Warner's copyright and trademarks. Warner won $2.57M in *Warner Bros. v. X One X* over film imagery. Turner holds RUBY SLIPPERS marks. [Loeb summary](https://www.loeb.com/en/insights/publications/2016/11/warner-bros-entertainment-inc-v-x-one-x-producti__) · [Reddie & Grose](https://www.reddie.co.uk/2025/12/03/the-ruby-slippers-gone-for-good/) |
| **Twenty Thousand Leagues (Nautilus)** | Verne (1870): public domain. | **Yes → "Nautilus"** | Brass, rivets, portholes, deep sea. | Don't copy Disney's 1954 submarine design. "Nautilus" is a fitness-equipment brand, but not in software themes. Low risk. |
| **The Great Gatsby** | 1925 novel: public domain since 1 Jan 2021. [Duke CSPD 2021](https://web.law.duke.edu/cspd/publicdomainday/2021/) | **Yes → "Gatsby"** | 1925 Art Deco: black lacquer, gold, sunbursts. | The 1974 and 2013 films are still under copyright (don't copy their posters or type). "GATSBY" is also a men's grooming brand, so see §10 on the name ("West Egg" is the fallback). |
| **Dracula** | Stoker (1897): public domain. | **Yes → "Dracula"** | Gothic: candlelight, velvet, oxblood, old gold. | No Universal 1931 look and no Bela Lugosi likeness (widow's peak, medallion, high-collared cape). California gives heirs a 70-year post-mortem publicity right (Civil Code §3344.1, enacted after *Lugosi v. Universal*). [Lugosi v. Universal](https://scocal.stanford.edu/opinion/lugosi-v-universal-pictures-28087) |
| **Frankenstein's monster** | Shelley (1818): public domain. | Yes, but not in v1 | Shelley's creature: yellowish skin, long black hair, galvanism, laboratory brass. | Universal's design (green flat-topped head, neck bolts, Jack Pierce make-up) is Universal's. The 1931 film enters US public domain on 1 Jan 2027, but its trademarks and licensing stay. [UBC IP analysis](https://iplaw.allard.ubc.ca/?p=9408) |
| **Mickey Mouse ("Steamboat '28")** | *Steamboat Willie* (1928): public domain since 1 Jan 2024, but only that black-and-white, gloveless, pie-eyed version. | **No, skip** | Nothing. | Disney's MICKEY MOUSE marks are live, and Disney says it will "protect against consumer confusion". A keyboard theme is the kind of product that implies endorsement. [NPR via KUOW](https://www.kuow.org/stories/steamboat-willie-is-now-in-the-public-domain-what-does-that-mean-for-mickey-mouse) · [Slashfilm](https://slashfilm.com/1482137/mickey-mouse-steamboat-willie-public-domain-disney) |
| **Winnie-the-Pooh** | 1926 Milne and Shepard: public domain since 2022; Tigger (1928) since 2024. | Possible, skip in v1 | Shepard's pencil look only. | Disney's red-shirt Pooh and its WINNIE THE POOH marks stay. Too close to Disney merchandise for a paid app. [Duke CSPD 2022](https://web.law.duke.edu/cspd/publicdomainday/2022/bcvpd/) |
| **Peter Pan** | 1911 novel: US public domain. The 1928 play script entered on 1 Jan 2024. | Possible, skip in v1 | Barrie's text and F. D. Bedford's 1911 illustrations. | **UK:** Great Ormond Street Hospital holds a perpetual royalty on performance, publication and broadcast of the play and its adaptations (CDPA 1988, Sched. 6). Disney's Peter Pan and Tinker Bell look is Disney's. [GOSH](https://www.gosh.org/about-us/peter-pan/copyright) |
| **Popeye** | 1929 *Thimble Theatre* Popeye: public domain since 1 Jan 2025 (no spinach; that arrived in 1931 or 1932). | **No, skip** | - | POPEYE marks are Hearst's (King Features). The Fleischer cartoons are still under copyright. [WDWNT](https://wdwnt.com/2025/01/popeye-the-sailor-enters-public-domain) |
| **Tintin** | *Land of the Soviets* (1929): Duke counts it public domain in the US as of 2025. Moulinsart and Tintinimaginatio **dispute** this (they say the term runs from first US publication, 1959 or 1989). | **No, skip** | - | Disputed copyright, plus the rightsholders' trademarks and well-known enforcement. [Belga](https://www.belganewsagency.eu/beloved-comic-character-tintin-enters-us-public-domain-with-certain-limitations) |
| **Zorro** | McCulley's 1919 to 1922 stories and the 1920 film: public domain. | **No, skip** | - | Zorro Productions Inc. holds US ZORRO marks and has fought users for years (*Cabell v. ZPI*; M&M's). The EU found its mark non-distinctive, but the US marks stand. [Loeb, Cabell](https://www.loeb.com/en/insights/publications/2018/05/cabell-v-zorro-productions-inc) · [Techdirt, EU](https://archive.techdirt.com/articles/20150707/05431631568/europe-frees-zorro-trademark-restrictions.shtml) |
| **Tarzan** | Early Burroughs novels (1912 onward): public domain. | **No, skip** | - | Edgar Rice Burroughs Inc. enforces TARZAN marks against public-domain uses (it sued Dynamite in 2012). [Techdirt](https://archive.techdirt.com/articles/20120228/18543417906/edgar-rice-burroughs-inc-using-trademark-law-to-prevent-use-public-domain-stories.shtml) |
| **The Little Prince** | 1943, first published in the US. **Under US copyright until 2039.** | **No** | - | The Saint-Exupéry estate also registers the characters as trademarks. [CCDigitalLaw](https://vmelab2.lu.usi.ch/wordpress_ccdigitallaw/?p=6614) · [IPKat](https://ipkitten.blogspot.com/2008/04/fight-for-seoul-rights-to-little-prince.html) |
| **Pinocchio (Collodi, 1883)** | Public domain, along with Enrico Mazzanti's illustrations. | Yes, not in v1 | Collodi's wooden puppet, Mazzanti's line. | Disney's 1940 design is Disney's. |
| **Robin Hood, King Arthur, Greek and Norse myth, Hercules** | Folklore and ancient sources, never owned. | Yes, not in v1 | Sherwood greens, Camelot heraldry, marble and laurel. | Don't copy any studio's version (Disney's *Hercules*, Marvel's Thor and Loki). |
| **1930 arrivals (2026): Betty Boop, Nancy Drew, Blondie, Pluto** | The 1930 versions are public domain. [Duke 2026](https://web.law.duke.edu/cspd/publicdomainday/2026/) | **No, skip** | - | Live trademarks: Fleischer Studios (BETTY BOOP), Simon & Schuster (NANCY DREW), King Features (BLONDIE), Disney (PLUTO). |

### 1.3 The shortlist that is clearly safe

Built in this spec: **221B** (Holmes), **Wonderland** (Tenniel's Alice), **Emerald City** (Baum and Denslow's Oz), **Nautilus** (Verne), **Gatsby** (Fitzgerald and 1925 Art Deco), **Dracula** (Stoker). For later: Frankenstein (Shelley's, not Universal's), Robin Hood, Camelot, Olympus, Pinocchio (Collodi's).

House rules for every story theme:

1. Use only the **original book's** look. Never a film, TV or game version.
2. **No characters' faces or figures**, not even public-domain ones. A theme is mood and material (gaslight, cards, emeralds, brass), not a portrait. That also keeps any trademark claim on a character's image out of it.
3. **The theme's name is a place, an object or an era** ("221B", "Wonderland", "Emerald City", "Nautilus"). Never a character's name used as a brand.
4. No catchphrases from films. No one's logo or type.
5. App Store Connect: theme names in screenshots and metadata stay generic ("vintage themes", "a Victorian study"). Don't name the characters.

### 1.4 Original archetypes: safe when original

A noir detective, a space captain, a cyberpunk city, a samurai or a masked hero at night is a genre, not a property. Copyright protects expression, not ideas or stock characters (*scènes à faire*). These are safe as long as the design is ours and avoids a franchise's specific marks:

- **Noir**: no Sam Spade or Marlowe names, no *Maltese Falcon* imagery.
- **Orbit** (space captain): no Star Trek LCARS panels (rounded orange and lavender bars), no Starfleet delta, no NASA "worm" or "meatball" logos, no named ships.
- **Overclock** (cyberpunk): don't call it "Cyberpunk". CYBERPUNK is a registered mark for games (R. Talsorian and CD PROJEKT). No 2077 yellow-and-cyan logo type.
- **Samurai**: no film, anime or game references (no *Ghost of Tsushima*, no *Seven Samurai* stills), and no real clan crests (*kamon*).
- **Rooftop**: see §1.1.

Brand names are out of names too. "Vintage Leica" is called **Rangefinder**, and it skips the red dot (a Leica trademark). The Olivetti vibe is called **Typewriter**. Bauhaus is called **Primary** (the word is used as a mark by unrelated companies; the style is free).

---

## 2. How themes work today

**History**

- `ab60d6c` (2026-09-16), "Keyboard themes derive from one board colour, like Gboard": twelve board colours (Stone, Lilac, Sky, Mint, Sand, Blush, Ink, Indigo, Midnight, Pine, Plum, Cocoa) and four gradients (dusk, ocean, ember, forest). Everything came from one seed (`KeyPalette.fromBoard`).
- `41b51ff`: the brand key follows the theme.
- `af38458` (2026-09-27): **colour themes and forced light and dark retired.** On iOS the painted board sat inside the system's tray and looked cut off. The Flutter screen now resets `themeBg` to `""` on load. iOS lost the Appearance row, and Android kept it.
- `git log -S keyTheme`: `e00902c`, `829092e`, `2bb3008`, `55bf1aa`, `77a6d7f`, `80383a7`, `5946b6f`, `ab60d6c`, `6258cfd`, `20da269`, `dbbd2c7`, `ab30741`.

**What is still in the code**

| Piece | iOS | Android | App |
|---|---|---|---|
| Settings | `SettingsStore.keyTheme` ("site" default, "glass"; legacy "classic" and "glow" migrate), `themeBg` ("" \| `color:#RRGGBB` \| `grad:<id>`), `keyBorders`, `keyClicks`, `appearance` | `Stores.kt` defaults: the same keys | `keyboard_screen.dart`: Look grid (Glyf, Glass), Borders switch, Sound and Haptic switches |
| Palette | `Glass` in `Design/GlassTokens.swift`: `keyColor`, `fillKey`, `fillKeyFn`, `fillKeyPressed`, `keyInk`, `boundDot`, `returnBlue`, `chipAccent`, `strokeKeyBorder`, `keyShadow*`, `surfaceCard`, `chromeDark`; `themeBgColors()` still parses `themeBg` | `GlyfKeyboardView.KeyPalette` (board, key, keyPressed, fn, fnPressed, ink, inkSoft, edge, card, darkChrome), `KeyPalette.ios(dark)` default, `fromBoard()`, `themedBackdrop()`, `GRADIENTS` | `core/theme.dart` (`KeyPalette`, Dart twin) |
| Board paint | `GlyfKeyboardViewController.applyBoardPaint()` (a `CAGradientLayer` under the keys); unused since the retirement | `themedBackdrop()` behind the whole IME | - |
| Keys | `Layout/KeyView.swift`: fill, 0.5 or 1pt border, shadow (opacity, offset 0,1, radius 0, `shadowPath`), label via `.systemFont`, SF Symbols `shift`, `delete.left`, `return` and arrows, `globe`, `face.smiling`; the press balloon (12pt corners) | `drawFace`, `drawShift`, `drawDelete`, `drawReturn`, `drawSmiley`; text via `interFace(context)` (Inter from `flutter_assets`) | - |
| Sound | `KeyboardView: UIInputViewAudioFeedback`, `UIDevice.current.playInputClick()` when `keyClicks` | `AudioManager.playSoundEffect(FX_KEYPRESS_STANDARD, 0.6f)` when `clicksOn` | "Sound on keypress" |
| Fonts | System (SF) only | Inter-Variable from `flutter_assets/assets/fonts` (`Glass.font`) | Inter (`pubspec.yaml`) |

The plumbing for "one palette drives every key" already exists on both sides. A theme replaces the seed-derived palette with an explicit one from the JSON. iOS keeps `boardColors` empty, so `applyBoardPaint()` leaves the sheet clear.

---

## 3. What a theme may change

| May change (per theme, per light or dark variant) | Never changes |
|---|---|
| Android board: a colour or a 2-stop gradient, plus an optional texture or illustration | Any size, gap, margin, radius, row or strip height (§0.1) |
| Key fill per class: letter, function (shift, delete, 123, emoji, globe, ABC, #+=), space, primary return; optional per-key overrides (shift, delete) | Font point sizes and weights' layout effect: no shrink-to-fit triggered by a theme |
| Pressed fills (derived, §5.2) | The g pill, the "glyf" watermark text, the Insert chip's layout |
| Key text (ink) and function-glyph colour | Key layout, rows, long-press menus, gestures, timings |
| Press popup fill and text | iOS: the strip's background (always clear) and any board paint |
| Strip text, Android strip background | Which keys exist per field type |
| Chip face and accent (the purple `chipAccent` today) | The blue return on iOS fields that ask for go, search, send or done; the theme's return colour replaces it **only when the theme is on** |
| Bound-key dot | Haptics |
| Key shadow: colour, alpha, offset 0 or 1pt, radius 0 (edge) or ≤4 (glow) | |
| Key border: none, or 1pt in one colour on chosen classes | |
| Key-face font family (OFL, embedded), at today's sizes | |
| Glyph style: `standard` (today), `light`, `bold` (§5.4) | |
| Key sound pack (§4.3) | |
| Key-face texture (Marble only, ≤3%) | |

---

## 4. Platform limits

### 4.1 iPhone keyboard extension

- **Memory.** Apple doesn't publish the extension limit. Glyf guards **45 MB** (`MemoryLogger.swift`, §M0), and community reports put jetsam at about 48 to 70 MB depending on device. Budget per theme: **≤ 1.5 MB resident**. That is one font of about 30 to 150 KB after subsetting, one texture tile of at most 256×256 (256 KB decoded), and the sound buffers (≤ 20 KB each). Load only the active theme. Release the previous theme's font, tile and sounds when the theme changes.
- **Fonts.** Copy the theme fonts into the **GlyfKeyboard target's** resources. The extension must not read Flutter's `App.framework/flutter_assets`. Register lazily with `CTFontManagerRegisterFontsForURL(url, .process, nil)` from `Bundle(for: KeyboardViewController.self)` the first time a theme needs one, and keep a set of what's registered. Then `UIFont(name: postScriptName, size: <today's size>)`, falling back to `.systemFont` if it returns nil. `UIAppFonts` in the extension's Info.plist also works, but it registers every font at launch and costs memory. Don't use it.
- **Textures.** None on iOS except Marble's key veins. Use **one** tile shared as `UIColor(patternImage:)` (or a `CALayer` with `contents` and `contentsScale`), never a full-board or per-key bitmap. A 1320×900 @3x bitmap is 4.7 MB.
- **Sound.** `UIDevice.playInputClick()` (today's) plays only the system click. A custom sample needs `AudioServicesCreateSystemSoundID` (create once per sample at theme load) and `AudioServicesPlaySystemSound`. These system sounds are silenced by the ring/silent switch, which is what we want. Reports say keyboard extensions get no audio without **Full Access**. Glyf already sets `RequestsOpenAccess`. Without Full Access, or if creating the sound fails, fall back to `playInputClick()`. Always obey `keyClicks`. Verify the Full Access behaviour on a device: the simulator doesn't tell. **Simulator result (iOS 26.5, iPhone 17 Pro Max, 2026-10-17):** with Full Access switched off, `AudioServicesCreateSystemSoundID` still loaded all four Typewriter samples and `AudioServicesPlaySystemSoundWithCompletion` reported each one played (completion after about the sample's length), and the theme itself (read from the App Group settings) still applied. So the simulator does not need Full Access for theme sounds, but it is known to be more permissive than a phone, so the keyboard keeps the rule above: theme sounds only with Full Access, the system click otherwise, until a device says the gate can go. [Apple, input clicks](https://developer.apple.com/library/archive/documentation/StringsTextFonts/Conceptual/TextAndWebiPhoneOS/InputViews/InputViews.html) · [2014 report on Full Access and clicks](https://mjtsai.com/blog/2014/12/06/developing-keyboards-for-ios)
- **Transparent pixels drop touches.** Any new layer must keep `Glass.touchableGrid` (1/255 alpha) behind the keys. A clear texture overlay must not replace it.
- **Reduce Transparency and Reduce Motion.** Glows (shadow radius > 0) are drawn only when both are off. Nothing in a theme animates.

### 4.2 Android IME

- Paint the board with `themedBackdrop()` behind the whole IME, including the gesture-nav inset. Textures go through `BitmapShader(tile, REPEAT, REPEAT)` or are drawn procedurally in `onDraw`, cached per size.
- Fonts load like Inter: `Typeface.Builder(assets, "flutter_assets/assets/fonts/<file>")`, with `setFontVariationSettings("'wght' N")` for variable files. They are the same files the Flutter app uses for previews, so there's one copy.
- Sound uses `SoundPool` with `AudioAttributes.USAGE_ASSISTANCE_SONIFICATION`, loaded at theme load. Play only when `clicksOn` is set and the ringer mode is `RINGER_MODE_NORMAL`. Today's `playSoundEffect` stays the "system" pack.

### 4.3 Sound packs

| Pack | Samples | Licence | Processing |
|---|---|---|---|
| `system` | Today's system click | - | none |
| `typewriter` | key [BMacZero 160678](https://freesound.org/people/BMacZero/sounds/160678/) (116 ms); return bell [eZZin 623435](https://freesound.org/people/eZZin/sounds/623435/) (a Remington bell) followed by the carriage return from [Nox_Sound 550340](https://freesound.org/people/Nox_Sound/sounds/550340/); delete is one keystroke from 550340 | CC0 (checked on each page, 2026-10-17) | trim to the transient, 3 ms fades, mono 44.1 kHz; letters ≤ 120 ms, the return ≤ 600 ms; normalise to -18 dBFS peak |
| `shutter` | [jgrzinich 155385](https://freesound.org/people/jgrzinich/sounds/155385/): its first 25 ms as a focus-ring "detent" on letters, one full shutter on return | CC0 | as above |
| `wood` | [husamalhomsi 500926](https://freesound.org/people/husamalhomsi/sounds/500926/) (61 ms); return pitched down 5 semitones | CC0 | as above |
| `mech` | one keystroke and the space-bar stroke from [EricsSoundschmiede 382057](https://freesound.org/people/EricsSoundschmiede/sounds/382057/) (Cherry blue) | CC0 | as above |
| `synth` | generated: 2.4 kHz square, 18 ms; return is two notes | none (ours) | render offline once |
| `sonar` | letters use the system click; return is a generated 1.2 kHz sine ping with a 280 ms decay | none (ours) | render offline once |

Files: iOS `.caf` (IMA4) ≤ 20 KB each in the GlyfKeyboard target; Android `.ogg` in `res/raw`. CC0 needs no attribution, but list each source URL in the app's acknowledgements anyway. That makes provenance easy to prove later. Delete never repeats a long sample: on auto-repeat, play every 4th time (today's rule) and only the short key sound.

### 4.4 Fonts

All 16 families are from Google Fonts under **OFL-1.1**. Each was checked in the `google/fonts` repo's `ofl/` folder on 2026-10-17. Ship rules:

- **No Reserved Font Name** (Courier Prime, Jost, Spectral, Prata, JetBrains Mono, Libre Caslon Text, IM Fell English, Cormorant Garamond, Shippori Mincho, Chakra Petch, Exo 2): **subset** to Basic Latin, Latin-1, General Punctuation and the currency signs the keyboard draws (`$ ₹ £ € ¥ ₩`), and **instance** variable fonts to the one weight. Use `fonttools`: `varLib.instancer`, then `pyftsubset --unicodes=U+0020-007E,U+00A0-00FF,U+2010-2027,U+20A9,U+20AC,U+20B9 --layout-features='*'`. Shippori Mincho is 8.7 MB as published (it carries Japanese) and must be subset.
- **With a Reserved Font Name** (Orbitron, Marcellus, Libre Baskerville, Limelight, and DM Serif Display, whose RFN is "Source"): ship the **file unmodified**. A subset is a Modified Version and couldn't keep the name. Together they come to about 470 KB.
- Bundle `OFL.txt` with each font and list them in the acknowledgements.

---

## 5. Colour model and contrast rules

### 5.1 Fields of a variant (as in the JSON)

`board.colors` (1 or 2 stops; `angle` in CSS degrees, 160 means top-left towards bottom), `letterKey`, `functionKey`, `spaceKey` (each with `fill` and `pressed`), `keyText`, `functionGlyph`, `returnPrimary` (`fill`, `text`, `pressed`), `keyOverrides` (`shift` and/or `delete`: `fill`, `glyph`, `pressed`), `popup` (`fill`, `text`), `strip` (`background`: a colour or `"board"`; `text`; iOS always clear), `chip` (`face`, `accent`), `boundDot`, `shadow` (`color`, `alpha`, `offsetY` 0 or 1, `radius` 0 or 2 to 4), `border` (`null` or `color`, `width` 1, `appliesTo`: letter, function, space, return).

**Which fields iOS uses:** everything except `board` and `strip.background`. On iOS, strip text, suggestions and panels keep today's sheet-based colours (`Glass.textPrimary` etc.). The theme recolours the chip, the dot and the keys.

**Primary return.** The theme's `returnPrimary` is used where iOS draws its blue return today (go, search, send, done; Android's IME actions). A plain return (⏎) and "next" use `functionKey` and `functionGlyph`.

**"Borders around keys".** If a theme has a `border`, it is always drawn and the switch is hidden for that theme. If not, the switch draws today's `strokeKeyBorder` at 1pt.

### 5.2 Derived colours (already computed in the JSON)

- Key pressed = `blend(fill, ink, 0.14)` in sRGB. This is today's iOS rule (`keyColor.blend(keyInk, 0.14)`).
- Return pressed = `blend(fill, #000, 0.18)`. This is today's `returnBluePressed`.
- Marble keys: the vein tile at ≤ 3% alpha in the ink colour.

### 5.3 Contrast rules (all checked by script; §7 has the numbers)

WCAG 2.x relative luminance, `(L1 + 0.05) / (L2 + 0.05)`.

- **Text ≥ 4.5:1**: key text on letter keys (at the texture's worst point for Marble), function glyphs, override glyphs, return text, popup text, strip text (each board stop), chip accent on chip face.
- **Non-text ≥ 3:1**: the bound-key dot on the letter key, and **every key class against the board and against the iPhone sheet of its mode**. The sheets are measured: light `#E2E4E8` and the forced paint `#D1D4D9`; dark `#1B1B1D` and `#292929`. Safari with a light page in dark mode draws `#424242`, which is reported in the JSON as information only.
- A key's boundary can come from its **fill**, its **1pt border**, or its **1pt bottom edge**: a shadow with offset 1, radius 0, composited over the board. The JSON records which one carried it (`…by`). Glows don't count.
- For comparison, Apple's own keys reach only **1.27:1** (white on `#E2E4E8`) and **1.66:1** (`#404041` on `#1B1B1D`). These themes are deliberately stricter. That is why pale light-mode keys have a visible 1pt edge (alpha 0.45 to 0.64) and some dark themes use a 1pt rim. See §10 for whether to keep it.

### 5.4 Glyph styles

Symbol point sizes stay as they are. Only the weight changes.

| Style | iOS (`UIImage.SymbolConfiguration` weight) | Android (stroke width in `drawShift`, `drawDelete`, `drawReturn`, `drawSmiley`) |
|---|---|---|
| `standard` | today's | today's |
| `light` | `.light` | × 0.8 |
| `bold` | `.semibold` | × 1.25 |

---

## 8. Implementation plan

### 8.1 Settings

- `keyTheme` gains the theme ids: `"site"` (Glyf, default), `"glass"`, or one of the 24 ids, e.g. `"typewriter"`. `themeBg` stays `""` (retired). Leave the Flutter reset in place.
- No new key for light and dark. iOS follows the host. Android uses the existing `appearance` (auto, light, dark).
- Unknown id falls back to `"site"`. This covers downgrades, and a theme removed later maps to `"site"` (the no-duplicate-entry-points rule: map old ids when moving).

### 8.2 Code

1. **Generate, don't transcribe.** One script reads `shared/themes/themes.json` and writes `app/ios/GlyfKeyboard/Design/Themes.generated.swift`, `app/android/.../ime/Themes.kt` and `app/lib/core/themes.dart`.
2. **iOS.** `Glass` reads the active theme variant (`Glass.theme: ThemeVariant?`). `fillKey`, `fillKeyFn`, `fillKeyPressed`, `keyInk`, `boundDot`, `returnBlue` (theme return when themed), `chipAccent`, `strokeKeyBorder`, `keyShadow*` and `surfaceCard` (= `chip.face`) return theme values when set and today's values otherwise. `boardColors` stays empty. `KeyView` takes the font name from the theme and the size from today's code. `KeyboardView` routes clicks through a `ThemeSound` player.
3. **Android.** `KeyPalette.fromTheme(variant)` builds the palette, and `themedBackdrop()` returns the board and texture. `drawFace` uses the theme typeface, and `onKeyClick` uses `ThemeSound`.
4. **App.** The Look grid lists Glyf, Glass, then the 24 themes, each tile drawn from the JSON (keys only on iOS, board on Android), with the theme name under it and no explainer lines. Tapping a tile writes `keyTheme`. "Borders around keys" is hidden when the theme has a border.
5. **Fonts:** subset and instance per §4.4 into `app/assets/fonts/themes/`, declare them in `pubspec.yaml` and copy them into the GlyfKeyboard target (sync script). **Sounds:** render into `app/ios/GlyfKeyboard/Sounds/` and `app/android/app/src/main/res/raw/`.

### 8.2a iOS: what was built (2026-10-17)

- Settings: a separate `skin` key (theme id, "" or missing = today's look) and `skinSound` (nil = on), instead of new `keyTheme` values, as agreed with the Android/Flutter side. `keyTheme` stays "site" or "glass"; a skin wins over Glass.
- `tools/gen_themes.py` writes `app/ios/GlyfKeyboard/Design/KeyboardThemes.swift` (named so, not `Themes.generated.swift`); `--check` fails when it is stale. Types, font registry, sound player and key textures are in `Design/KeyboardTheme.swift`.
- `Glass` hands out the variant's colours for the keys (letter, function, space, the shift/delete overrides), inks, primary return, press popup (the press callout, the accent popup and the glide word), chip face and accent, dot, shadow and border. Panels, cards and the strip keep the sheet's colours; their shadows keep the plain `keyShadow*` tokens, and keys use `Glass.keyFaceShadow`. Text on a themed chip follows the face's own lightness (Rangefinder, Matte, Terminal and Overclock put a dark chip on the light sheet). The accent popup's pick wears the theme's return colour.
- Fonts: `tools/gen_theme_fonts.py` (needs `fonttools`) fetched the 16 files from google/fonts, instanced and subset the non-RFN ones as §4.4 says, and copied the 5 RFN files unmodified; 1.3 MB in all with their OFL texts (`<Family>-OFL.txt`). Registered with `CTFontManagerRegisterFontsForURL(.process)` only for the picked theme, the previous one unregistered. Orbitron and Libre Baskerville keep their axis; the weight is asked for at run time (Orbitron at 500). No font needed a vertical nudge, and none shrinks: "m", "w", "M" and "W" fit 33.5pt at 24.5 and 22pt in every theme face (`KeyboardThemeTests`).
- Sounds: `tools/gen_theme_sounds.py` synthesises every pack (no Freesound takes), 22.05 kHz IMA4 `.caf`, 4 to 11 KB each, into `GlyfKeyboard/Sounds/`. Played on key down when `keyClicks`, `skinSound` and Full Access allow; otherwise the system click. Delete's repeat plays its short sample every 4th time.
- Rose Gold's satin: at -4% lightness the dark variant's function glyph falls to 4.04:1, so the gradient's bottom stops at -0.5% there (4.5:1 kept); light runs the full +4% to -4%.
- On the simulator the 1pt edge shadow (offset 1, radius 0) renders with a soft fringe of about 1pt round the key's sides and bottom, all in the gaps; key fills and borders sit on exactly the default look's pixels.

### 8.3 Tests

- **Geometry unchanged:** for every theme, `KeyboardLayout.frames` (iOS) and the Android key rects match the default exactly. `KeyMetricsTests` must still pass.
- **No shrink:** for every themed font, the widest letters ("m", "w", "M", "W") at 24.5 and 22pt fit a 33.5pt key without `adjustsFontSizeToFitWidth` kicking in. Record any that don't, and don't change the size.
- **Contrast:** `shared/themes/check_contrast.py` (and a unit test doing the same on each platform) recomputes §7 from the JSON and fails on any value under the minimums.
- **Memory:** cycle all 24 themes in one keyboard session on a device. The footprint must stay under the 45 MB guard (`GLYF_MEM`).
- **Sound:** with `keyClicks` off, nothing plays. With the ring switch silent, nothing plays. Without Full Access, the system click plays.
- Scenario QA: one screenshot per theme × light and dark in Messages (iOS) and on the emulator (Android).

---

## 9. Considered and cut

- **Linen**: merged into Sahara's light variant. Pale linen on the iOS sheet looked like the default.
- **Midnight Velvet**: velvet went to Dracula's board, and the navy is already in Ocean and Rooftop.
- **Chrome**: metallic gradients on keys looked cheap and failed text contrast somewhere along the gradient. Rangefinder's satin chrome covers it.
- **Glass Aurora**: the existing Glass look already does translucent keys, and on iOS a translucent key over the system sheet can't show an aurora.
- **Ink & Paper**: Wonderland (engraving) and Samurai (washi) cover it.
- **Neon Noir**: merged into Overclock. **Art Deco gold**: that's Gatsby.
- **Steamboat '28**: skipped (§1.2, Disney's marks). **Web Slinger**: replaced by Rooftop (§1.1).

---

## 10. Decisions for Arpit

1. **iPhone: keys-only themes on the system sheet (recommended), or try a painted board again?** Painting brings back the cut tray you rejected on 2026-09-27. This spec paints only on Android.
2. **Strict key contrast (≥ 3:1) or Apple-like?** Strict means light themes get a crisp 1pt edge under each key and some dark themes a 1pt rim. Apple's own keyboard is 1.27:1 and has neither. Strict reads better outdoors. Apple-like looks flatter.
3. **Free or paid?** For example, Glyf, Glass and four themes free, and the rest with Plus or Max.
4. **Names.** "Gatsby" is also a men's grooming brand. Keep it, or use "West Egg"? "Nautilus" is also a fitness brand (low risk).
5. **A lawyer's read of §1.3** before the six story themes ship. Outside the US: Doyle, Carroll and Tenniel, Baum and Denslow, Verne and Stoker all died before 1931, so their work is free in life-plus-70 countries too. Fitzgerald died in 1940, so Gatsby has been free there since 2011. Life-plus-100 Mexico is the exception (until 2041).
6. **Custom key sounds** may need Full Access on iOS (to verify on a device). Ship the packs with the system-click fallback?
7. **More later?** Ready to design next: Frankenstein (Shelley's lab, not Universal's), Sherwood (Robin Hood), Camelot, Olympus, Pinocchio (Collodi), and more materials (Linen, Velvet, Concrete, Denim).

---
