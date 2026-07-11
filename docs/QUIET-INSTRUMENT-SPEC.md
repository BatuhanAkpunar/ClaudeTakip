# ClaudeTakip v1.4 Reskin Spec — "Quiet Instrument"

Reskin only. Zero layout/IA changes. Every value below is a drop-in constant swap or one-line modifier change. All colors given as light / dark (code already branches on `colorScheme`).

**One accent strategy:** neutral ink for all chrome (titles, chevrons, tracks, axes); green/amber/red reserved exclusively for *state* (rings, gauges, pills, status cloud); per-window identity hues appear only on *data fills and their value text* (Sonnet violet, Extra blue). Coral `claudeAccent #D97856` retreats to brand-only: logo, plan pill, toggles, Check button. It leaves titles, segmented control, and the Extra bar.

---

## 1. Canvas + card surfaces — `DesignTokens.swift`

| Token | Current | New |
|---|---|---|
| `Radius.card` | 10 | **12**, and add `style: .continuous` to every `RoundedRectangle(cornerRadius: DT.Radius.card)` |
| `PopoverBackground` fill | light `#F0F0F5` / dark `#1C1C1F` | light **`#F5F5F7`** (0.96, 0.96, 0.97) / dark **`#161618`** (0.086, 0.086, 0.094) |
| `GlassCard` fill | light `white.opacity(0.85)` / dark `white.opacity(0.12)` | light **`white.opacity(0.98)`** / dark **`white.opacity(0.07)`** |
| `GlassCard` border | 2-stop gradient stroke, 0.5pt | **uniform hairline**, 0.5pt: light `black.opacity(0.06)` / dark `white.opacity(0.10)` — delete the `LinearGradient` |
| `GlassCard` shadow | light `black 0.08, r6, y3` / dark `black 0.35, r10, y3` | light **`black 0.05, r5, y2`** / dark **`black 0.30, r8, y2`** |
| `ThemedDivider` | primary 0.10 / 0.15 | primary **0.06 / 0.10** |

## 2. Palette — `DT.Colors`

- Keep `statusGreen #34C759`, `statusOrange #FF9500`, `statusRed #FF3B30` (Apple system ramp, correct semantics). Keep `statusColor(for:)` thresholds.
- `sonnetPurple #8C5CF5` → **`#6E62E5`** (0.43, 0.38, 0.90) — same identity, less neon.
- Extra row adopts the **existing `unlimitedBlue`** (`#1B67B2` light / `#4D8FD9` dark) as its identity hue in both limited and unlimited states; promote it to `DT.Colors.extraBlue`. Coral removed from the bar.
- Section titles (see 3) drop coral for ink.
- AI card (untouched layout): shadow `accent 0.30, r10` → **`accent 0.15, r6`**; border 1.5pt → **1pt**.

## 3. Typography ladder — SF Pro, floor 10pt

| Role | Current | New |
|---|---|---|
| Section titles (`sectionTitle`, chart header) | 10.5 semibold, tracking 0.6, coral 0.85 | **11 semibold, tracking 0.8, `.primary.opacity(0.45)`** |
| Gauge sub-titles ("CURRENT SESSION (5 HRS)") | 10 medium, tracking 0.5, primary 0.50 | 10 medium, tracking **0.6**, primary **0.55** |
| Donut center | 21 heavy + stacked 11 "%" | **18 semibold `.monospacedDigit()`** + inline **10 medium** "%" (see 4) |
| Rate number | 16.5 heavy | **17 semibold `.monospacedDigit()`**; suffix "x" 11 bold → **11 medium** |
| Bar values ("12%") | 12 bold | **11 semibold `.monospacedDigit()`** |
| Countdown times | 11 semibold | 11 semibold + **`.monospacedDigit()`** |
| Captions ("resets in") | 11 medium, primary 0.70 | **10 medium, primary 0.45** |
| App name (bottom bar) | 13 bold, primary 0.70 | **12.5 semibold, primary 0.75** |

Apply `.monospacedDigit()` to every numeric that refreshes (donut centers, rates, %, times) — kills value jitter.

## 4. Donut gauges (`donutCard`)

- Track: `color.opacity(0.10)`, 7pt → **`.primary.opacity(0.08)`, 5pt** (neutral track, only the fill carries state color).
- **Delete the 12pt glow arc entirely** (the second `Circle().trim`).
- Main arc: 7pt linear-gradient → **5pt**, `AngularGradient(colors: [color.opacity(0.80), color], center: .center, startAngle: .degrees(-90), endAngle: .degrees(-90 + 360 * usage))`, round cap kept.
- Frame 60×60 → **64×64** (air replaces glow).
- Center: replace the stacked `VStack(spacing: -2)` with `HStack(alignment: .lastTextBaseline, spacing: 0.5)` — number **18 semibold `.primary.opacity(0.90)`**, "%" **10 medium `.primary.opacity(0.45)`**. The ring alone signals health; green-on-green ends, green-when-healthy stays.
- Resets line: glyph `hourglass.bottomhalf.filled` 8pt → **`clock` 9pt .medium `.primary.opacity(0.40)`**; time 11 semibold **primary 0.80 + monospacedDigit**; "resets in" 11 medium 0.70 → **10 medium 0.45**.

## 5. SONNET / EXTRA rows

- Track: `primary.opacity(0.10)`, height 11 → **`primary.opacity(0.08)`, height 6** (matches `DT.Size.barHeight`).
- Fill: leading→trailing gradient → **solid** identity hue (`#6E62E5` / `extraBlue`), height 6.
- Row labels: 9.5 bold tracking 0.5 → **10 semibold, tracking 0.6, primary 0.60**. "$4.20 / $25" stays 10.5 mono, primary → **0.55**.
- % value: 12 bold → **11 semibold monospacedDigit**, identity hue, width 30 → **32, `.trailing`**.
- **Truncation fix** ("2d 2…", "26d…"): label column `width: 95` → **80**; bar `width: 120` → **106**; hourglass glyph 13pt → **`clock` 9pt** (unified with donuts, `.primary.opacity(0.40)`); add **`.fixedSize()`** and `.layoutPriority(1)` to the reset `Text`. Frees ~35pt; "2d 23h" renders whole. No string changes.
- Unlimited pill: keep, border added — `strokeBorder(extraBlue.opacity(0.18), 0.5pt)`.

## 6. Speedometers (`SpeedometerGaugeView`)

- `arcStroke` 11 → **6**. Track `primary.opacity(0.06)` → **0.08**.
- **Delete the glow pass** (the `arcStroke + 2` stroke inside the segment loop) — keep the 50-segment gradient ramp as-is (it is the state semantics).
- End cap: delete the 3 glow layers; keep **4pt solid dot + 2pt white center** only.
- Ideal tick: 1.5pt `primary 0.35` → **1pt `primary 0.30`**; **delete the 7.5pt "1x" canvas label** (violates the 10pt floor; "Ideal = 1.0x" in the card header already says it). Header text: 9.5 mono primary 0.70 → **10 medium mono primary 0.45**.
- Deviation row: neutral color `primary 0.50` → **0.55**; sizes unchanged.
- Severity pills: 11.5 bold, bg 0.15 → **11 semibold**, bg **`color.opacity(0.12)`** + hairline `strokeBorder(color.opacity(0.20), 0.5pt)`, padding h7/v5 → **h9/v4**.

## 7. Segmented control, collapsible header, chart

- **Segmented** (`chartTabPicker`): capsules → **`RoundedRectangle(cornerRadius: 7, style: .continuous)`** chips in an **r9** container (native macOS segmented look). Container bg `primary 0.04` → **0.05**, padding 3 → **2**. Active chip: coral `0.18` → light **`Color.white` + shadow `black 0.10, r3, y1` + hairline `black.opacity(0.06)`** / dark **`white.opacity(0.16)`**. Active text 10.5 bold tracking 0.3 → **11 semibold, tracking 0, primary 0.85**; inactive **11 medium primary 0.45**.
- **Collapsible header**: title per 3; chevron coral 0.6 → **`.primary.opacity(0.35)`, 10pt semibold**.
- **Chart** (`DetailedChartView`): area gradient `0.90/0.60/0.25/0.03` → **`0.28/0.16/0.06/0.02`**; line 2.5pt + 5pt glow → **2pt, delete glow stroke**; end dot: keep one glow layer `(r5, 0.12)` + **7pt dot** + white center; excess fill red `0.25/0.35` → **`0.18/0.28`**; ideal diagonal and grid unchanged; projection line unchanged, marker glow 3 layers → **2** (`(r8, 0.12), (r5, 0.30)`). Axis labels 9pt mono `primary 0.7` → **10pt medium mono `primary 0.45`**; y-axis column width 32 → **36**. "Estimated Overrun"/time labels keep 10/10.5.

## 8. Bottom bar

- Icons unified: **all outline, 13pt, .medium** — `person.crop.circle`, `info.circle`, **`gearshape`** (drop `.fill`), `power`. Idle `.primary.opacity(0.40)` (replaces `.tertiary`/`0.5` mix), active/hover `.primary.opacity(0.85)`; quit hover `Color.red 0.8` → **`DT.Colors.statusRed.opacity(0.90)`**. Spacing 11 → **14**.
- Status cloud: unchanged (filled + colored) — it is the bar's single status light.
- Logo 20 → **18**; name per 3; dot `primary 0.30` → **0.25**; refresh text 11 semibold 0.55 → **11 medium 0.50**.

## 9. The three modern touches (already woven in)

1. **Uniform hairlines** — every border in the app is one 0.5pt line (`black 0.06` / `white 0.10`); no gradient strokes anywhere.
2. **Unified countdown glyph** — one `clock` at 9pt/.medium/`primary 0.40` in all three reset locations, replacing two hourglass variants at three sizes.
3. **Angular gradient on donut arcs + monospaced digits everywhere** — the only remaining "glow-era" effects are the two semantic red markers (projection, cap) in the chart; everything else is flat, thin, and still.

**Explicitly deleted decoration:** donut glow arc, speedometer glow pass, chart line glow, end-cap glow stacks (donut/speedo), gradient card borders, gradient bar fills, coral titles, canvas "1x" microtext.
## Addendum (owner feedback round 1)

1. **Contrast pass**: all `.primary` text opacities raised — 0.45→0.62,
   0.50→0.65, 0.55→0.70, 0.60→0.74 ("yazılar okunmuyor"). Rate-card titles
   also got minimumScaleFactor(0.85) to end the pre-existing truncation.
2. **Aurora gradients** ("aurora gradient tonları olabilirdi"): new DT
   partners auroraTeal/Pink/Magenta/Violet/Cyan + auroraPartner(for:).
   Donut arcs sweep status hue → aurora partner with a soft same-hue glow
   (r3, 0.30); Sonnet bar fills purple→violet, Extra bar blue→cyan
   (linear, leading→trailing) with glow (r3, 0.35); bars 6→7 pt.
