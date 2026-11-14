# Design rules

Read this before changing the app (Sources/MacJanitor) or the site (site/).
Adapted from "27 Copy-Paste Prompts to Fix AI Slop UI" (Sam Vllaco), step 26, for a
native macOS menu-bar app.

## Rule 1: change this file first

A new rule, or a change to one, goes in here before it goes in the code. If the code
and this file disagree, this file wins. If a request breaks a rule, say so and ask
before doing it.

## Colour

- Neutral first: window, card, stroke, divider and text come from `Palette` in
  Theme.swift. Cards are never coloured.
- One accent, glacier blue (`Palette.accent` / `accentFill`): the main button, links,
  the ring, "on" dots and the kept pin. Nothing else.
- Status colours carry one meaning each: `warning` (amber) for "needs attention",
  `critical` (red) for low disk, errors and the destructive Clean now button.
  A status colour marks an icon, a dot or a short line, never a whole surface.
- No gradients, no glows, no coloured shadows. No terracotta or orange accent.

## Type

- One font: the system font. Monospaced only for paths.
- Four sizes, from `TextSize`: 26 title (page titles, the panel headline number),
  17 heading (section values such as tile sizes, detail titles), 13 body,
  11 label (secondary lines, captions, footnotes).
- Two weights: regular and semibold. Use weight before adding a size.
- No uppercase "eyebrow" labels above headings. No script or handwritten fonts.

## Spacing

- 4-point scale: 4, 8, 12, 16, 24, 32, 48. Nothing in between.
- Lines that belong to one row sit 4 apart. Rows and cards in a stack sit 8 apart.
  Sections sit 24 apart.
- Panel: 14 outer inset (fixed by the concentric corners below), 12 inside cards.
  Windows: 32 page margin, 16 inside rows, hairlines start at the row's text.

## Surfaces and corners

- One card look: `.surface()` (neutral fill, 1px stroke, no shadow), or `Card` for
  divided rows.
- The panel has a 22pt corner. Cards and the main button use `Metrics.cardRadius`
  (12) and nothing else. Secondary buttons are capsules. Nothing inside a card is
  rounder than the card.
- No badges or pills above headings. `StatusPill` sits only at a row's trailing edge.

## Icons

- SF Symbols, outlined, everywhere: sidebars, rows, tiles, banners.
- Filled symbols mean state only: the warning triangle and error octagon, and the
  pin of an item you keep. Never use a filled symbol as decoration.
- Icons take the secondary text colour (`Palette.icon`) unless they carry status.
- No emoji in the interface.

## Layout

- The 3x3 category grid is the panel's core; keep it. Values and labels line up
  across each row: the value line is a fixed height and the label reserves two lines.
- Elsewhere, prefer one card with rows over a grid of identical small cards.

## Copy

- Say what it does, for whom, in plain words. Numbers over adjectives.
- Buttons: a verb plus what happens ("Clean 17.7 GB…", "Allow", "Stop keeping").
  Never "Submit", "Click here" or a vague "Fix".
- Errors say what happened and what to do next. Empty states say what will appear
  and offer one action.
- One word per thing on every screen.
- No em dashes. No "it's not X, it's Y" constructions.

## States

- Every clickable element shows the pointing-hand cursor (`pointingCursor()`), and
  not-allowed when disabled.
- Hover lightens a card with `Palette.cardHover`; disabled controls use the tertiary
  style. Loading shows a spinner and a word, never a blank space.

## Site

- The same palette, one accent, four type sizes and the 4-point scale apply to
  site/. The sizes are tokens in styles.css: `--title` (36 to 56), `--heading`
  (24 to 32), `--body` 16, `--label` 13. Weights 400 and 600.
- Radii: 12 for buttons and nav links, 24 for cards and dialogs. A card gets a 1px
  inset line or a soft shadow, never both.
- One primary button in the hero. A second action appears only when it leads
  somewhere real (the video button stays hidden until assets/demo.mp4 exists).
- Every link and button gets `cursor: pointer`. The folder toy (toy.js, toy.css)
  keeps its own styling.

- Show the real app: screenshots and the panel rendered from the app's own snapshot
  fixtures, never an invented mockup.

## Checking a change

Render the snapshots (`MacJanitor --snapshot <dir>`) light and dark, compare them with
main side by side, and score the screens on: colour, type, spacing, headline, cards,
icons, surfaces, copy, states, proof and fit. Revert anything that scores worse.
