// Themes: the tradeable story behind a row, and how hot it is.
//
// A small-cap premarket board usually runs one story at a time -- crypto
// treasuries, then AI, then biotech headlines -- and the money is in knowing
// which story is live before the fourth ticker in it gaps. This file turns the
// newest headline (or a pinned ticker) into a theme, the Finviz sector into a
// sector, then scores each group's heat from what its members actually did.
//
// Used by the engine (ScreenerEngine.qml), the table (Screener.qml) and the
// scorecard measures (scorecards.js).
//
// Two things to know about the design:
//
//   1. Heat is judged on RUNNERS, not members. A hot theme day pulls in
//      laggards, so counting members (or the share of them that ran) reads
//      the day a theme ignites as quiet. A group is hot when more of its
//      stocks ran than it usually has on a day like this -- "usually" being
//      its share of all the runners on the board, so a market-wide rally
//      does not light every group (2025 back test, 2026-10-24).
//
//   2. Every session counts, including the ones where a group had nobody
//      on the board. Its baseline, its "day N" and how long it has been
//      since anything ran are all counted in sessions or calendar days, not
//      in the days it happened to appear.
.pragma library

// ── glyphs ─────────────────────────────────────────────────
// SVG fragments on a 24x24 box, drawn to read at 13px in a panel table --
// which is the only size that matters, and is where a pickaxe or a derrick
// turns to mush. {C} is the heat colour and {F} is the fill ("none" for a
// quiet or burnt theme), so one fragment covers every state. {B} is a line
// drawn on top of the fill: dark when filled, the heat colour when not.
//
// Breeze ships none of these, so they live here rather than as icon names.
// That also means they survive any icon theme and tint to the heat colour.
var glyphs = {
    pill:    '<g transform="rotate(-45 12 12)"><path d="M12 8.5H5.5A3.5 3.5 0 0 0 5.5 15.5H12Z" fill="{F}"/><rect x="2" y="8.5" width="20" height="7" rx="3.5" fill="none" stroke="{C}" stroke-width="1.6"/><path d="M12 8.5V15.5" stroke="{C}" stroke-width="1.6"/></g>',
    bolt:    '<path d="M13 1 4 14h6l-1 9 9-13h-6l1-9z" fill="{F}" stroke="{C}" stroke-width="1.7" stroke-linejoin="round"/>',
    atom:    '<ellipse cx="12" cy="12" rx="10" ry="4" fill="none" stroke="{C}" stroke-width="1.7"/>'
           + '<ellipse cx="12" cy="12" rx="10" ry="4" fill="none" stroke="{C}" stroke-width="1.7" transform="rotate(60 12 12)"/>'
           + '<ellipse cx="12" cy="12" rx="10" ry="4" fill="none" stroke="{C}" stroke-width="1.7" transform="rotate(-60 12 12)"/>'
           + '<circle cx="12" cy="12" r="2.6" fill="{C}"/>',
    drop:    '<path d="M12 2.5c4.2 6.3 6.5 9.8 6.5 12.8a6.5 6.5 0 0 1-13 0c0-3 2.3-6.5 6.5-12.8z" fill="{F}" stroke="{C}" stroke-width="1.7" stroke-linejoin="round"/>',
    ship:    '<path d="M3 14h18l-3 7H6z M12 14V5 M12 5 19 8 12 11z M8 14v-3h8v3" fill="{F}" stroke="{C}" stroke-width="1.7" stroke-linejoin="round"/>',
    gem:     '<path d="M12 22 2.5 9 6 2.5h12L21.5 9z" fill="{F}" stroke="{C}" stroke-width="1.7" stroke-linejoin="round"/>'
           + '<path d="M2.5 9h19M8.5 9 12 22M15.5 9 12 22M6 2.5 8.5 9M18 2.5 15.5 9" fill="none" stroke="{C}" stroke-width="1.3"/>',
    chip:    '<path d="M7 7h10v10H7z M4 10h3 M4 14h3 M17 10h3 M17 14h3 M10 4v3 M14 4v3 M10 17v3 M14 17v3" fill="{F}" stroke="{C}" stroke-width="1.7" stroke-linejoin="round"/>',
    node:    '<path d="M12 2 21 7v10l-9 5-9-5V7z M12 9.5a2.5 2.5 0 1 0 0 5 2.5 2.5 0 0 0 0-5z" fill="{F}" fill-rule="evenodd" stroke="{C}" stroke-width="1.7" stroke-linejoin="round"/>',
    coin:    '<path d="M12 2a10 10 0 1 0 0 20 10 10 0 0 0 0-20z M9 7h4a3 3 0 0 1 0 6H9z M9 13h4.5a3 3 0 0 1 0 6H9z" fill="{F}" fill-rule="evenodd" stroke="{C}" stroke-width="1.7" stroke-linejoin="round"/>'
           + '<path d="M9 5v14 M12 4v2 M12 18v2" fill="none" stroke="{C}" stroke-width="1.4"/>',
    shield:  '<path d="M12 2 20 5v7c0 5-3.5 8.5-8 10-4.5-1.5-8-5-8-10V5z" fill="{F}" stroke="{C}" stroke-width="1.7" stroke-linejoin="round"/>',
    rocket:  '<path d="M12 2c4 3.5 6 8 6 13l-3 3H9l-3-3c0-5 2-9.5 6-13z M12 8.5a2 2 0 1 0 0 4 2 2 0 0 0 0-4z" fill="{F}" fill-rule="evenodd" stroke="{C}" stroke-width="1.7" stroke-linejoin="round"/>'
           + '<path d="M9 18l-3 4 3-1 M15 18l3 4-3-1" fill="{F}" stroke="{C}" stroke-width="1.7" stroke-linejoin="round"/>',
    leaf:    '<path d="M21 3C10 3 4 8 4 15c0 3 1 5 1 5s2-9 16-13C14 10 9 13 7 20 18 20 21 11 21 3z" fill="{F}" stroke="{C}" stroke-width="1.7" stroke-linejoin="round"/>',
    cannabis: '<path d="M12.00 19.20 L12.63 17.97 L13.14 16.74 L12.95 15.51 L13.30 14.29 L12.99 13.06 L13.25 11.83 L12.89 10.60 L13.10 9.37 L12.70 8.14 L12.88 6.91 L12.45 5.69 L12.61 4.46 L12.17 3.23 L12.00 2.00 L12.00 2.00 L12.00 2.00 L11.83 3.23 L11.39 4.46 L11.55 5.69 L11.12 6.91 L11.30 8.14 L10.90 9.37 L11.11 10.60 L10.75 11.83 L11.01 13.06 L10.70 14.29 L11.05 15.51 L10.86 16.74 L11.37 17.97 ZM12.00 19.20 L13.03 18.44 L13.95 17.63 L14.23 16.53 L15.00 15.66 L15.17 14.51 L15.87 13.60 L15.98 12.44 L16.63 11.50 L16.71 10.32 L17.33 9.38 L17.40 8.19 L18.00 7.23 L18.04 6.03 L18.35 4.95 L18.35 4.95 L18.34 4.95 L17.74 5.90 L16.88 6.74 L16.58 7.82 L15.73 8.66 L15.44 9.76 L14.62 10.61 L14.36 11.71 L13.57 12.58 L13.36 13.71 L12.63 14.60 L12.49 15.76 L11.86 16.70 L11.88 17.92 ZM12.00 19.20 L12.12 17.92 L12.14 16.70 L11.51 15.76 L11.37 14.60 L10.64 13.71 L10.43 12.58 L9.64 11.71 L9.38 10.61 L8.56 9.76 L8.27 8.66 L7.42 7.82 L7.12 6.74 L6.26 5.90 L5.66 4.95 L5.65 4.95 L5.65 4.95 L5.96 6.03 L6.00 7.23 L6.60 8.19 L6.67 9.38 L7.29 10.32 L7.37 11.50 L8.02 12.44 L8.13 13.60 L8.83 14.51 L9.00 15.66 L9.77 16.53 L10.05 17.63 L10.97 18.44 ZM12.00 19.20 L13.11 19.05 L14.15 18.81 L14.71 18.04 L15.63 17.68 L16.11 16.83 L16.98 16.40 L17.42 15.51 L18.26 15.05 L18.68 14.12 L19.49 13.64 L19.89 12.70 L20.69 12.20 L21.08 11.25 L21.66 10.50 L21.66 10.50 L21.66 10.50 L20.86 11.00 L19.87 11.29 L19.29 12.03 L18.31 12.33 L17.75 13.09 L16.78 13.41 L16.24 14.19 L15.30 14.54 L14.79 15.36 L13.89 15.75 L13.43 16.63 L12.61 17.11 L12.27 18.11 ZM12.00 19.20 L11.73 18.11 L11.39 17.11 L10.57 16.63 L10.11 15.75 L9.21 15.36 L8.70 14.54 L7.76 14.19 L7.22 13.41 L6.25 13.09 L5.69 12.33 L4.71 12.03 L4.13 11.29 L3.14 11.00 L2.34 10.50 L2.34 10.50 L2.34 10.50 L2.92 11.25 L3.31 12.20 L4.11 12.70 L4.51 13.64 L5.32 14.12 L5.74 15.05 L6.58 15.51 L7.02 16.40 L7.89 16.83 L8.37 17.68 L9.29 18.04 L9.85 18.81 L10.89 19.05 ZM12.00 19.20 L12.85 19.59 L13.66 19.86 L14.25 19.47 L15.01 19.59 L15.57 19.09 L16.30 19.12 L16.84 18.56 L17.56 18.55 L18.08 17.95 L18.79 17.92 L19.31 17.30 L20.01 17.24 L20.53 16.60 L21.13 16.24 L21.13 16.23 L21.13 16.23 L20.43 16.29 L19.64 16.08 L19.03 16.44 L18.25 16.25 L17.65 16.63 L16.88 16.46 L16.29 16.87 L15.53 16.74 L14.95 17.20 L14.21 17.12 L13.66 17.66 L12.95 17.69 L12.46 18.39 ZM12.00 19.20 L11.54 18.39 L11.05 17.69 L10.34 17.66 L9.79 17.12 L9.05 17.20 L8.47 16.74 L7.71 16.87 L7.12 16.46 L6.35 16.63 L5.75 16.25 L4.97 16.44 L4.36 16.08 L3.57 16.29 L2.87 16.23 L2.87 16.23 L2.87 16.24 L3.47 16.60 L3.99 17.24 L4.69 17.30 L5.21 17.92 L5.92 17.95 L6.44 18.55 L7.16 18.56 L7.70 19.12 L8.43 19.09 L8.99 19.59 L9.75 19.47 L10.34 19.86 L11.15 19.59 Z M12 19.2 V22" fill="{F}" stroke="{C}" stroke-width="0.5" stroke-linejoin="round" stroke-linecap="round"/>',
    drone: '<path d="M9 9.5 5.5 5.5M15 9.5 18.5 5.5M9 14.5 5.5 18.5M15 14.5 18.5 18.5" stroke="{C}" stroke-width="1.5" stroke-linecap="round" fill="none"/><circle cx="5" cy="5" r="2.6" fill="none" stroke="{C}" stroke-width="1.5"/><circle cx="19" cy="5" r="2.6" fill="none" stroke="{C}" stroke-width="1.5"/><circle cx="5" cy="19" r="2.6" fill="none" stroke="{C}" stroke-width="1.5"/><circle cx="19" cy="19" r="2.6" fill="none" stroke="{C}" stroke-width="1.5"/><rect x="8.5" y="9" width="7" height="6" rx="1.5" fill="{F}" stroke="{C}" stroke-width="1.5"/>',
    tank: '<rect x="2.5" y="14" width="19" height="5" rx="2.4" fill="{F}" stroke="{C}" stroke-width="1.5"/><path d="M7 14a5 5 0 0 1 10 0z" fill="{F}" stroke="{C}" stroke-width="1.5" stroke-linejoin="round"/><path d="M12 10.5H21.5" stroke="{C}" stroke-width="2.2" stroke-linecap="round" fill="none"/><circle cx="6.5" cy="16.5" r="0.9" fill="{B}"/><circle cx="9.5" cy="16.5" r="0.9" fill="{B}"/><circle cx="12.5" cy="16.5" r="0.9" fill="{B}"/><circle cx="15.5" cy="16.5" r="0.9" fill="{B}"/><circle cx="18.5" cy="16.5" r="0.9" fill="{B}"/>',
    ai: '<path d="M12 6V2.8M12 18v3.2M6 12H2.8M18 12h3.2" stroke="{C}" stroke-width="1.5" stroke-linecap="round" fill="none"/><circle cx="12" cy="2.5" r="1.3" fill="{C}"/><circle cx="12" cy="21.5" r="1.3" fill="{C}"/><circle cx="2.5" cy="12" r="1.3" fill="{C}"/><circle cx="21.5" cy="12" r="1.3" fill="{C}"/><circle cx="12" cy="12" r="6" fill="{F}" stroke="{C}" stroke-width="1.5"/><path d="M8.6 14.8 10.4 9.4 12.2 14.8M9.2 13.1H11.6M13.9 9.4V14.8" stroke="{B}" stroke-width="1.4" stroke-linejoin="round" fill="none"/>',
    bitcoin: '<circle cx="12" cy="12" r="9.8" fill="{F}" stroke="{C}" stroke-width="1.6"/><path d="M8.8 6.8H13.4C15.2 6.8 16.1 7.9 16.1 9.3C16.1 10.2 15.7 10.9 14.9 11.2C16 11.5 16.6 12.3 16.6 13.5C16.6 15.2 15.5 16.2 13.7 16.2H8.8ZM8.8 11.2H14.4" stroke="{B}" stroke-width="1.9" stroke-linejoin="round" fill="none"/><path d="M10.8 4.6V6.8M13.6 4.6V6.8M10.8 16.2V18.4M13.6 16.2V18.4" stroke="{B}" stroke-width="1.6" stroke-linecap="round" fill="none"/>',
    mining: '<rect x="2.5" y="6.5" width="19" height="11" rx="1.5" fill="{F}" stroke="{C}" stroke-width="1.5"/><circle cx="15.5" cy="12" r="3.8" fill="none" stroke="{B}" stroke-width="1.1"/><g transform="rotate(0 15.5 12)"><path d="M15.5 12C14.4 10.4 14.6 8.6 16.2 8.4C16.6 10 16.4 11 15.5 12Z" fill="{B}"/></g><g transform="rotate(90 15.5 12)"><path d="M15.5 12C14.4 10.4 14.6 8.6 16.2 8.4C16.6 10 16.4 11 15.5 12Z" fill="{B}"/></g><g transform="rotate(180 15.5 12)"><path d="M15.5 12C14.4 10.4 14.6 8.6 16.2 8.4C16.6 10 16.4 11 15.5 12Z" fill="{B}"/></g><g transform="rotate(270 15.5 12)"><path d="M15.5 12C14.4 10.4 14.6 8.6 16.2 8.4C16.6 10 16.4 11 15.5 12Z" fill="{B}"/></g><circle cx="15.5" cy="12" r="0.9" fill="{B}"/><path d="M5.5 9.6H10.5M5.5 14.4H10.5" stroke="{B}" stroke-width="1.2" stroke-linecap="round" fill="none"/>',
    tower: '<path d="M7 21.5 12 8.5 17 21.5M9.4 15.5H14.6M8.2 19H15.8M9.4 15.5 14.6 19M14.6 15.5 9.4 19" stroke="{C}" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" fill="none"/><circle cx="12" cy="8.5" r="1.4" fill="{F}" stroke="{C}" stroke-width="1.2"/><path d="M9.3 5.8A3.5 3.5 0 0 0 9.3 11.2M14.7 5.8A3.5 3.5 0 0 1 14.7 11.2" stroke="{C}" stroke-width="1.5" stroke-linecap="round" fill="none"/><path d="M7 3.8A6.5 6.5 0 0 0 7 13.2M17 3.8A6.5 6.5 0 0 1 17 13.2" stroke="{C}" stroke-width="1.5" stroke-linecap="round" fill="none"/>',
    vault: '<rect x="3" y="3" width="18" height="18" rx="3" fill="{F}" stroke="{C}" stroke-width="1.6"/><circle cx="11" cy="12" r="5.4" fill="none" stroke="{B}" stroke-width="1.3"/><path d="M11 6.6V8M11 16V17.4M5.6 12H7M15 12h1.4" stroke="{B}" stroke-width="1.2" stroke-linecap="round" fill="none"/><circle cx="11" cy="12" r="1.5" fill="{B}"/><path d="M11 12H17.6" stroke="{B}" stroke-width="1.8" stroke-linecap="round" fill="none"/><circle cx="6" cy="6" r="0.9" fill="{B}"/><circle cx="18" cy="6" r="0.9" fill="{B}"/><circle cx="6" cy="18" r="0.9" fill="{B}"/><circle cx="18" cy="18" r="0.9" fill="{B}"/>',
    anon: '<path d="M12 2C8.4 2 6.2 4.8 6.2 8.8c0 2.2.7 3.8 1.9 4.8C5.6 14.4 4 16 4 18.8V22h16v-3.2c0-2.8-1.6-4.4-4.1-5.4 1.2-1 1.9-2.6 1.9-4.8C18 4.8 15.6 2 12 2z" fill="{F}" stroke="{C}" stroke-width="1.4" stroke-linejoin="round"/><ellipse cx="12" cy="9.4" rx="2.6" ry="3.4" fill="{B}"/>',
    dot:     '<circle cx="12" cy="12" r="6" fill="{F}" stroke="{C}" stroke-width="1.7"/>',
    // A newspaper with an X through it: a runner with no news (2026-10-26;
    // the anonymous figure stays crypto's privacy glyph).
    nonews:  '<path d="M3 4h13.5v15.5a2 2 0 0 0 2 2H5a2 2 0 0 1-2-2z" fill="{F}" stroke="{C}" stroke-width="1.5" stroke-linejoin="round"/>'
           + '<path d="M16.5 8.5h4.5v11a2 2 0 0 1-4.5 0" fill="none" stroke="{C}" stroke-width="1.5" stroke-linejoin="round"/>'
           + '<path d="M5.5 7h8.5" stroke="{B}" stroke-width="1.6" stroke-linecap="round"/>'
           + '<path d="M6 10.5 13.5 18.5M13.5 10.5 6 18.5" stroke="{B}" stroke-width="2.2" stroke-linecap="round"/>',
    // A globe: a listing from outside the US.
    globe:   '<circle cx="12" cy="12" r="9.5" fill="{F}" stroke="{C}" stroke-width="1.6"/>'
           + '<path d="M2.5 12h19M12 2.5c-5 3.2-5 15.8 0 19M12 2.5c5 3.2 5 15.8 0 19M12 2.5v19M4.3 7h15.4M4.3 17h15.4" stroke="{B}" stroke-width="1.1" fill="none"/>',
    // Crypto. Inner detail is cut out (evenodd) or left unfilled, so it
    // still reads when the glyph is drawn solid.
    smile:   '<path d="M12 2.5a9.5 9.5 0 1 0 0 19 9.5 9.5 0 0 0 0-19z M9 7.6a1.5 1.5 0 1 0 0 3 1.5 1.5 0 0 0 0-3z M15 7.6a1.5 1.5 0 1 0 0 3 1.5 1.5 0 0 0 0-3z M7.3 13.2h9.4a4.7 4.7 0 0 1-9.4 0z" fill="{F}" fill-rule="evenodd" stroke="{C}" stroke-width="1.6" stroke-linejoin="round"/>',
    layers:  '<path d="M12 2.5 21.5 7.5 12 12.5 2.5 7.5z" fill="{F}" stroke="{C}" stroke-width="1.7" stroke-linejoin="round"/>'
           + '<path d="M2.5 12 12 17l9.5-5 M2.5 16.5 12 21.5l9.5-5" fill="none" stroke="{C}" stroke-width="1.7" stroke-linejoin="round"/>',
    dollar:  '<circle cx="12" cy="12" r="9.5" fill="{F}" stroke="{C}" stroke-width="1.7"/>'
           + '<path d="M15 8.6c-.6-1-1.7-1.6-3-1.6-1.6 0-2.9.9-2.9 2.2 0 3.1 6 1.8 6 5 0 1.4-1.3 2.4-3.1 2.4-1.3 0-2.5-.6-3.1-1.6 M12 5.3v13.4" fill="none" stroke="{B}" stroke-width="1.7" stroke-linecap="round"/>',
    // Sectors.
    bank:    '<path d="M12 2.5 21.5 7.5h-19z M4 9.5h3v8H4z M10.5 9.5h3v8h-3z M17 9.5h3v8h-3z M2.5 19.5h19v2.5h-19z" fill="{F}" stroke="{C}" stroke-width="1.5" stroke-linejoin="round"/>',
    factory: '<path d="M2.5 21.5V11l5.5 3.5V11l5.5 3.5V11l5.5 3.5V3.5h3v18z" fill="{F}" stroke="{C}" stroke-width="1.7" stroke-linejoin="round"/>',
    house:   '<path d="M12 2.5 2 11h3v10.5h5V15h4v6.5h5V11h3z" fill="{F}" stroke="{C}" stroke-width="1.7" stroke-linejoin="round"/>',
    bag:     '<path d="M4.5 8h15l-1.2 13.5H5.7z" fill="{F}" stroke="{C}" stroke-width="1.7" stroke-linejoin="round"/>'
           + '<path d="M8.5 10.5V6.5a3.5 3.5 0 0 1 7 0v4" fill="none" stroke="{B}" stroke-width="1.7" stroke-linecap="round"/>',
    apple:   '<path d="M12 7.5c-2.3-2-7.5-1.6-7.5 4.3 0 4.7 3.1 9.7 5.3 9.7 1.1 0 1.4-.6 2.2-.6s1.1.6 2.2.6c2.2 0 5.3-5 5.3-9.7 0-5.9-5.2-6.3-7.5-4.3z" fill="{F}" stroke="{C}" stroke-width="1.7" stroke-linejoin="round"/>'
           + '<path d="M12 7.5c0-2.3 1.2-4 3.5-4.8" fill="none" stroke="{C}" stroke-width="1.7" stroke-linecap="round"/>',
    chat:    '<path d="M3 4h18v12H10l-5.5 4.5V16H3z" fill="{F}" stroke="{C}" stroke-width="1.7" stroke-linejoin="round"/>',
    cube:    '<path d="M12 2 21 7 12 12 3 7z" fill="{F}" stroke="{C}" stroke-width="1.7" stroke-linejoin="round"/>'
           + '<path d="M3 7v10l9 5 9-5V7 M12 12v10" fill="none" stroke="{C}" stroke-width="1.7" stroke-linejoin="round"/>'
}


// One glyph as an image source. Qt renders an SVG data URI straight into an
// Image and caches it per URL, so a glyph is only rasterised once per
// colour -- no icon files, no graphical-effects import for the tint.
// `edge` (optional) draws the lines in a darker shade than the fill, so a
// light fill still stands off a light background. `crossed` adds the
// diagonal stroke that marks a burnt theme, so burnt never relies on grey
// against blue alone.
function icon(glyph, colour, fill, crossed, edge) {
    const frag = glyphs[glyph] || glyphs.dot
    const line = fill && edge ? edge : colour
    return "data:image/svg+xml;utf8," + encodeURIComponent(
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">'
        + frag.replace(/stroke="\{C\}"/g, 'stroke="' + line + '"').replace(/\{C\}/g, colour)
              .replace(/\{F\}/g, fill ? colour : "none")
              .replace(/\{B\}/g, fill ? "#1b1e20" : colour)
        + (crossed ? '<path d="M3 21 21 3" stroke="' + colour + '" stroke-width="2.4" stroke-linecap="round"/>' : "")
        + '</svg>')
}
// The cross-out alone, for drawing over a custom icon.
function crossIcon(colour) {
    return "data:image/svg+xml;utf8," + encodeURIComponent(
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">'
        + '<path d="M3 21 21 3" stroke="#1b1e20" stroke-opacity="0.5" stroke-width="4.4" stroke-linecap="round"/>'
        + '<path d="M3 21 21 3" stroke="' + colour + '" stroke-width="2.4" stroke-linecap="round"/></svg>')
}

// Settings → Themes can replace a glyph with any icon: a name from the
// icon theme, or a file (SVG best; PNG if it is simple and square).
// `icons` is {theme id: {icon, keep}}. `keep` shows the icon in its own
// colours with the heat as a ring; otherwise it is tinted like a glyph.
function custom(theme, icons) {
    const m = icons || {}
    const c = m[theme.id]
    return c && c.icon ? c : null
}
// The glyph drawn for a theme: the one chosen for it in Settings → Themes
// (a sector, a crypto category or a built-in theme), else its own.
function glyphName(theme, icons) {
    const c = (icons || {})[theme.id]
    return c && c.glyph ? c.glyph : theme.glyph
}
function iconSource(s) {
    return s && s.charAt(0) === "/" ? "file://" + s : s
}

// ── themes: what a stock is running ON ───────────────────────────────────
// A theme is an identifiable pattern among the runners (Matt, 2026-10-26):
// AI headlines, oil and gas stocks on geopolitical fear, runners with no
// news at all, foreign low-float listings. Naming it helps; the pattern is
// the thing. A theme is matched by any of:
//   - words in the newest headline, or an industry it lists ("what it is
//     about": either will do when both are given), and
//   - traits, all of which must hold (`when`): news or no news in the last
//     24 hours, foreign or a list of countries, float, price, market cap,
//     how recently it listed;
// or a ticker pinned to it by hand. A theme of traits alone is allowed (no
// news; foreign low-float). A stock can be on several themes at once; its
// row shows the hottest. What a company IS lives in the sector layer below.
// Users define their own in Settings → Themes (the `customThemes` setting);
// until they do, this starter set stands in.
//
// Before 2026-10-24 this list also held industry-shaped themes (Biotech,
// Oil & gas, Shipping, Semis) and matched Finviz industries, which filed
// every software company -- Adobe, Intuit -- under AI. Those moved to the
// sector layer. Ids are kept where a theme carried on, so its history does.
//
// A theme: { id, name, glyph, words: [...], industries: [...], when: {...},
//            tickers: [{symbol, from}...], market: "stocks" | "crypto",
//            ramp: "" (the global colours) | a ramp key, on }
// when: { news: "" | "none" | "some", foreign: bool, countries: [...],
//         floatMax, priceMin, priceMax, capMax, ipoDays } -- 0 or missing = no limit.
//
// Words are matched as whole words, ignoring case (see headlineMatches):
//   "nuclear"            the word itself
//   "drone*"             any word starting so: drone, drones
//   "eth | sol"          either
//   "eth + holdings"     both, within 60 characters of each other
// The crypto treasury rule is the last two together: the 2025 wave's
// follow-up releases name a coin and an action ("Acquires 176,271 ETH",
// "Grows Treasury to 1.819 Million SOL"), not the announcement phrase, and
// the phrase alone caught 13% of its run-day releases.
var cryptoCoins = "bitcoin | btc | ether | ethereum | eth | solana | sol | bnb | trx | tron | ton | tao | bittensor"
    + " | chainlink | link | worldcoin | wld | hype | hyperliquid | doge | dogecoin | sui | litecoin | ltc | xrp"
    + " | avax | ena | crypto | cryptocurrency | digital asset | token"
var cryptoActions = "treasury | holdings | holds | holder | reserve | acquires | purchase | purchases | buys | accumulates"
var starterThemes = [
    { id: "crypto",    name: "Crypto treasury", glyph: "coin",
      words: [cryptoCoins + " + " + cryptoActions, "treasury strategy", "treasury reserve asset"] },
    { id: "btcminers", name: "Bitcoin miners",  glyph: "cube",
      words: ["bitcoin mining", "bitcoin miner*", "btc miner*", "hashrate", "hash rate", "exahash*", "mining rig*", "self-mining"] },
    { id: "ai",        name: "AI",              glyph: "ai",
      words: ["artificial intelligence", "ai", "gpu*", "inference", "data center*", "datacenter*", "llm*",
              "large language", "agentic", "neural", "h100", "h200", "supercomput*"] },
    { id: "nuclear",   name: "Nuclear / SMR",   glyph: "atom",
      words: ["smr*", "small modular", "reactor*", "nuclear", "enrichment", "uranium", "fuel assembl*"] },
    { id: "power",     name: "Power & grid",    glyph: "bolt",
      words: ["megawatt*", "gigawatt*", "behind-the-meter", "behind the meter", "power purchase", "grid interconnect*",
              "interconnection", "fuel cell*", "substation*", "power transformer*"] },
    { id: "minerals",  name: "Critical minerals", glyph: "gem",
      words: ["rare earth*", "critical mineral*", "antimony", "graphite", "lithium", "offtake", "black mass"] },
    { id: "defense",   name: "Drones & defense", glyph: "drone",
      words: ["drone*", "uav*", "munition*", "missile*", "department of defense", "dod", "counter-uas", "defense contract*"],
      industries: defenseIndustries() },
    { id: "space",     name: "Space",           glyph: "rocket",
      words: ["satellite*", "launch vehicle*", "orbit", "orbital", "spacecraft", "lunar"] },
    { id: "cannabis",  name: "Cannabis",        glyph: "cannabis",
      words: ["cannabis", "cannabinoid*", "thc", "cbd", "dispensar*", "marijuana", "psilocybin"] }
].concat(patternStarters())
// The starters that are patterns rather than headline words, added
// 2026-10-26. Kept apart so a saved theme list can be given them once.
function patternStarters() {
    return [
        { id: "nonews",    name: "No-news runners",   glyph: "nonews", words: [], when: { news: "none" } },
        { id: "foreignlf", name: "Foreign low-float", glyph: "globe", words: [], when: { foreign: true, floatMax: 10e6 } },
        { id: "oil",       name: "Oil & gas",         glyph: "drop", words: [], industries: oilIndustriesList() }
    ]
}
// Functions, not vars: starterThemes above is built before a var here is set.
function oilIndustriesList() { return ["Oil & Gas E&P", "Oil & Gas Integrated", "Oil & Gas Midstream", "Oil & Gas Refining & Marketing",
                     "Oil & Gas Drilling", "Oil & Gas Equipment & Services"] }
// Defense also takes its industry, so an arms maker with no headline counts.
function defenseIndustries() { return ["Aerospace & Defense"] }
// Kept for lookup(); the starter set under its old name.
var catalog = starterThemes

// The glyphs a theme or sector can be drawn with, for the editor.
var glyphNames = Object.keys(glyphs)

// Your themes, or the starter set when the setting has never been saved
// ("" -- not "[]": deleting every theme leaves you with none). Pins saved as
// plain strings before pins were dated count from the start.
function loadThemes(cfg) {
    const raw = cfg && cfg.customThemes
    let l = null
    if (raw) {
        try { l = JSON.parse(raw) } catch (e) {}
    }
    if (!Array.isArray(l)) l = JSON.parse(JSON.stringify(starterThemes))
    return l.map(t => Object.assign({}, t, { tickers: (t.tickers || []).map(p => typeof p === "string" ? { symbol: p, from: "" } : p) }))
}
// Your sectors: { id ("u-…"), name, glyph, industries: [...], tickers: [...], ramp, on }.
function loadSectors(cfg) {
    try {
        const l = JSON.parse((cfg && cfg.customSectors) || "[]")
        if (Array.isArray(l)) return l
    } catch (e) {}
    return []
}

// ── pins ─────────────────────────────────────────────────────────────────
// A pin is {symbol, from}: the ticker is on the theme from that day on
// (from "" = always), so pinning BMNR today does not file its days before
// the treasury news under the theme when the history is re-tagged.
function pinSymbol(p) { return typeof p === "string" ? p : (p && p.symbol) || "" }
function pinSymbols(theme) { return ((theme && theme.tickers) || []).map(pinSymbol).filter(s => s) }
function hasPin(theme, sym) { return pinSymbols(theme).indexOf(sym) >= 0 }
// Pinned on `day` ("YYYY-MM-DD"; omitted = now).
function pinnedOn(theme, sym, day) {
    const l = (theme && theme.tickers) || []
    for (let i = 0; i < l.length; i++) {
        if (pinSymbol(l[i]) !== sym) continue
        const from = typeof l[i] === "string" ? "" : (l[i].from || "")
        return !day || !from || day >= from
    }
    return false
}
// The pins for a list of symbols: ones already pinned keep their day, new
// ones start on `day`.
function setPins(theme, symbols, day) {
    const old = (theme && theme.tickers) || []
    return symbols.map(s => {
        const p = old.find(x => pinSymbol(x) === s)
        return p ? (typeof p === "string" ? { symbol: p, from: "" } : p) : { symbol: s, from: day || "" }
    })
}
function togglePin(theme, sym, day) {
    const l = pinSymbols(theme)
    return Object.assign({}, theme, { tickers: setPins(theme, l.indexOf(sym) >= 0 ? l.filter(x => x !== sym) : l.concat([sym]), day) })
}

// ── matching ─────────────────────────────────────────────────────────────
function escapeRe(s) { return s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&") }
// One alternative as a pattern: whole words, a trailing * for any ending.
// A word boundary is only required where the term itself starts or ends in
// a letter or digit, so "ai-" still matches "AI-powered" but not "Thai-".
function termRe(w) {
    let s = lc(w).trim().replace(/\s+/g, " ")
    const star = s.charAt(s.length - 1) === "*"
    if (star) s = s.slice(0, -1).trim()
    if (!s) return null
    const pre = /^[a-z0-9]/.test(s) ? "(?:^|[^a-z0-9])" : ""
    const post = !star && /[a-z0-9]$/.test(s) ? "(?=$|[^a-z0-9])" : ""
    return new RegExp(pre + "(" + escapeRe(s).replace(/ /g, "\\s+") + ")" + post, "g")
}
// A word list entry, compiled once: [[alternatives of part 1], [part 2]...].
var ruleCache = {}
function rule(word) {
    const k = String(word || "")
    if (!(k in ruleCache)) {
        const parts = k.split("+").map(p => p.split("|").map(termRe).filter(r => r)).filter(p => p.length)
        ruleCache[k] = parts
    }
    return ruleCache[k]
}
// Where each part's terms start in `h` (lower case): [[positions]...].
function positions(parts, h) {
    return parts.map(alts => {
        const at = []
        for (let i = 0; i < alts.length; i++) {
            const re = alts[i]
            re.lastIndex = 0
            let m
            while ((m = re.exec(h)) !== null) {
                at.push(m.index + m[0].length - m[1].length)
                if (m[0].length === 0) re.lastIndex++
            }
        }
        return at
    })
}
// Does one entry match? Every part has to appear, all within `span`
// characters of each other.
function ruleMatches(word, h, span) {
    const parts = rule(word)
    if (!parts.length) return false
    const at = positions(parts, h)
    if (at.some(a => !a.length)) return false
    if (at.length === 1) return true
    // Sliding window over every (position, part) pair, in order.
    const all = []
    at.forEach((a, k) => a.forEach(p => all.push([p, k])))
    all.sort((x, y) => x[0] - y[0])
    const count = at.map(() => 0)
    let have = 0
    for (let lo = 0, hi = 0; hi < all.length; hi++) {
        if (count[all[hi][1]]++ === 0) have++
        while (all[hi][0] - all[lo][0] > (span || 60)) { if (--count[all[lo][1]] === 0) have--; lo++ }
        if (have === at.length) return true
    }
    return false
}
// Does a headline carry one of a theme's words? Theme words are tried
// first and win: for some stories the financing IS the catalyst (a
// treasury company's PIPE or registered direct), so the noise list below
// no longer vetoes a headline that names a theme.
function headlineMatches(theme, headline) {
    const h = lc(headline)
    if (!h) return false
    const w = theme.words || []
    for (let i = 0; i < w.length; i++) if (w[i] && ruleMatches(w[i], h, 60)) return true
    return false
}

// Does a stock fit a theme's pattern? `f` is what is known about it:
// { headline, industry, sector (id), country, float, price, cap,
//   news (true / false / null = not known yet), ipoDays }. Pins are handled
// by the caller. A trait that is not known yet does not match: a stock whose
// news has not been looked up is not "no news".
function hasPattern(t) {
    return (t.words || []).some(w => w) || (t.industries || []).length > 0 || traitCount(t.when) > 0
}
function traitCount(w) {
    if (!w) return 0
    let n = 0
    if (w.news === "none" || w.news === "some") n++
    if (w.foreign) n++
    if (w.countries && w.countries.length) n++
    for (const k of ["floatMax", "priceMin", "priceMax", "capMax", "ipoDays"]) if (w[k] > 0) n++
    return n
}
function themeMatches(t, f) {
    if (!t || !f || !hasPattern(t)) return false
    if (t.sectors && t.sectors.length && t.sectors.indexOf(f.sector) < 0) return false
    const words = (t.words || []).filter(w => w), inds = t.industries || []
    if (words.length || inds.length) {
        const byWords = words.length > 0 && headlineMatches(t, f.headline)
        const byInd = inds.length > 0 && !!f.industry && inds.indexOf(f.industry) >= 0
        if (!byWords && !byInd) return false
    }
    return traitsPass(t.when || {}, f)
}
// Which part matched: "words" when the headline did (what sticky membership
// follows), else "pattern".
function matchedBy(t, f) {
    return (t.words || []).some(w => w) && headlineMatches(t, f.headline) ? "words" : "pattern"
}
function traitsPass(w, f) {
    if (w.news === "none" && f.news !== false) return false
    if (w.news === "some" && f.news !== true) return false
    if (w.foreign && !(f.country && f.country !== "USA")) return false
    if (w.countries && w.countries.length && w.countries.indexOf(f.country) < 0) return false
    if (w.floatMax > 0 && !(f.float > 0 && f.float <= w.floatMax)) return false
    if (w.priceMin > 0 && !(f.price >= w.priceMin)) return false
    if (w.priceMax > 0 && !(f.price > 0 && f.price <= w.priceMax)) return false
    if (w.capMax > 0 && !(f.cap > 0 && f.cap <= w.capMax)) return false
    if (w.ipoDays > 0 && !(f.ipoDays >= 0 && f.ipoDays <= w.ipoDays)) return false
    return true
}

// ── sectors ──────────────────────────────────────────────────────────────
// The second layer: every stock has a sector, whatever its headline, so the
// board's make-up shows at a glance and a sector that keeps turning up heats
// like a theme -- the cue to look for the catalyst behind it (Matt,
// 2026-10-24). Finviz's eleven sectors, matched on its name exactly; a
// per-ticker override (Settings → Themes) beats it. Ids start "s-" so a
// sector never shares a history with a theme. Crypto's equivalent is its
// CoinGecko category (cryptoCatalog below).
var sectorCatalog = [
    { id: "s-energy",      name: "Energy",                 glyph: "drop",    finviz: "Energy" },
    { id: "s-utilities",   name: "Utilities",              glyph: "bolt",    finviz: "Utilities" },
    { id: "s-health",      name: "Healthcare",             glyph: "pill",    finviz: "Healthcare" },
    { id: "s-tech",        name: "Technology",             glyph: "chip",    finviz: "Technology" },
    { id: "s-financial",   name: "Financial",              glyph: "bank",    finviz: "Financial" },
    { id: "s-materials",   name: "Basic Materials",        glyph: "gem",     finviz: "Basic Materials" },
    { id: "s-industrials", name: "Industrials",            glyph: "factory", finviz: "Industrials" },
    { id: "s-realestate",  name: "Real Estate",            glyph: "house",   finviz: "Real Estate" },
    { id: "s-cyclical",    name: "Consumer Cyclical",      glyph: "bag",     finviz: "Consumer Cyclical" },
    { id: "s-defensive",   name: "Consumer Defensive",     glyph: "apple",   finviz: "Consumer Defensive" },
    { id: "s-comms",       name: "Communication Services", glyph: "chat",    finviz: "Communication Services" }
]
// "s-" Finviz sectors, "u-" your own.
function isSector(id) { const s = String(id); return s.indexOf("s-") === 0 || s.indexOf("u-") === 0 }
function sectorById(id) {
    const s = sectorCatalog.find(x => x.id === id)
    return s ? { id: s.id, name: s.name, glyph: s.glyph } : null
}
function sectorFor(finviz) {
    const s = sectorCatalog.find(x => x.finviz === finviz)
    return s ? { id: s.id, name: s.name, glyph: s.glyph } : null
}

// Any id's name and glyph, whichever layer it is from: a theme, a sector,
// or a crypto category. Rows stored before 2026-10-24 may still carry an
// old "other:<industry>" id; those read as unnamed.
function lookup(id) {
    const all = catalog.concat(sectorCatalog, cryptoCatalog)
    const t = all.find(x => x.id === id)
    if (t) return { id: t.id, name: t.name, glyph: t.glyph }
    if (String(id).indexOf("other:") === 0) return { id: id, name: String(id).slice(6), glyph: "dot", unnamed: true }
    return { id: id, name: String(id), glyph: "dot" }
}

// ── crypto themes ────────────────────────────────────────────────────────
// From CoinGecko's categories (ids as its /coins/categories/list gives
// them, checked 2026-10-24). A coin sits in many categories -- FET is AI and
// Layer 1 -- so the order decides: the narrow stories first, the broad
// platform buckets last. A coin in none of these has no theme. Ids start
// "c-" so a crypto theme never shares a history with a stock one ("ai"
// stocks and AI tokens are different boards).
var cryptoCatalog = [
    // First: a stablecoin is also tagged DeFi and the like, but it trades as
    // a dollar -- the only move it makes is a depeg, which is its own story.
    { id: "c-stable",   name: "Stablecoins",       glyph: "dollar", cats: ["stablecoins"] },
    { id: "c-meme",     name: "Meme coins",        glyph: "smile",  cats: ["meme-token"] },
    { id: "c-ai",       name: "AI tokens",         glyph: "ai",   cats: ["artificial-intelligence", "ai-agents"] },
    { id: "c-depin",    name: "DePIN",             glyph: "tower",  cats: ["depin", "storage"] },
    { id: "c-rwa",      name: "Real-world assets", glyph: "gem",    cats: ["real-world-assets-rwa"] },
    { id: "c-gaming",   name: "Gaming",            glyph: "rocket", cats: ["gaming"] },
    { id: "c-privacy",  name: "Privacy",           glyph: "anon",   cats: ["privacy-coins", "zero-knowledge-zk"] },
    { id: "c-oracle",   name: "Oracles",           glyph: "atom",   cats: ["oracle"] },
    { id: "c-defi",     name: "DeFi",              glyph: "vault",  cats: ["decentralized-finance-defi"] },
    { id: "c-exchange", name: "Exchange tokens",   glyph: "bolt",   cats: ["exchange-based-tokens"] },
    { id: "c-l2",       name: "Layer 2",           glyph: "layers", cats: ["layer-2"] },
    { id: "c-l1",       name: "Layer 1",           glyph: "cube",   cats: ["layer-1"] }
]
function isCrypto(id) { return String(id).indexOf("c-") === 0 }
function cryptoCategories() {
    const out = []
    for (let i = 0; i < cryptoCatalog.length; i++)
        for (let j = 0; j < cryptoCatalog[i].cats.length; j++) out.push(cryptoCatalog[i].cats[j])
    return out
}
function classifyCrypto(categories) {
    const have = categories || []
    for (let i = 0; i < cryptoCatalog.length; i++) {
        const t = cryptoCatalog[i]
        for (let j = 0; j < t.cats.length; j++)
            if (have.indexOf(t.cats[j]) >= 0) return { id: t.id, name: t.name, glyph: t.glyph, from: "category" }
    }
    return null
}

// Headline words that are a financing, a listing problem or a lawsuit rather
// than a story. Since 2026-10-24 they no longer stop a headline that names a
// theme from matching it (headlineMatches); isNoise() is kept for the
// back-test tools, which count how many run-day headlines are only this.
var noise = ["reverse split", "regains compliance", "minimum bid price", "delisting",
             "securities law violation", "class action", "investigates", "at-the-market",
             "atm program", "registered direct", "warrant inducement", "nasdaq notification",
             "annual meeting", "proxy", "dividend declar"]

function lc(s) { return (s || "").toString().toLowerCase() }

function isNoise(headline) {
    const h = lc(headline)
    for (let i = 0; i < noise.length; i++) if (h.indexOf(noise[i]) >= 0) return true
    return false
}

// ── heat ─────────────────────────────────────────────────────────────────
// A theme is established by its record, not by one morning (Matt,
// 2026-10-26): "a theme takes at least 3 days to establish, preferably a
// week", and a hot one lasts weeks or months. So:
//
//   RUNNER    a member up `ranPct`% on the day (its best moment, premarket
//             included -- a premarket fade is still a tradeable pattern), or
//             `noNewsPct`% with no news in the last 24 hours, on at least
//             `runRvol`x its usual volume. A move on thin volume does not count.
//   HOT       runners on `hotDays` of the last `hotWindow` sessions, and more
//             often than the group usually has them (`liftX` x its rate in the
//             sessions before, once it has `minHistory` of them) -- which is
//             what stops a broad pattern like "no news" lighting every week.
//             Once hot, it stays hot while runners turn up on `stayDays` of
//             the last `hotWindow` sessions: a long theme has quiet days.
//   BUILDING  a runner on at least one of the last `hotWindow` sessions.
//   BURNT     was hot, and nothing has run for `deadDays` calendar days.
//   QUIET     none of these.
//
// Tunables. Settings → Themes writes over these (the `themeTuning` JSON,
// plus `themeDeadDays` and `themeStickySessions`).
var defaults = {
    ranPct:         30,   // a member with news "ran" at this % on the day
    noNewsPct:      60,   // ... and one with no news in 24 hours at this
    runRvol:        5,    // ... on at least this many times its usual volume (0 = any)
    hotDays:        3,    // HOT: sessions with a runner, of the last hotWindow
    hotWindow:      5,    // the sessions the record is read over
    stayDays:       1,    // stays HOT while runners turn up on this many of the last hotWindow
    liftX:          1.5,  // HOT: runner sessions at least this many times the group's usual rate
    deadDays:       14,   // calendar days with no runner before a theme that was hot is dead
    stickySessions: 10,   // sessions a ticker stays on a theme after its headline last matched
    keepDays:       30,   // sessions of history kept per group (never fewer than 2 x deadDays)
    minHistory:     10,   // sessions before the group's usual rate is trusted
    window:         20    // sessions the usual rate is read over
}
// Retired 2026-10-26 with the record rules: hotRan, bldX (a day's runner
// count). Retired 2026-10-24: minHistory's old meaning, minMembers,
// hotFollow, coldTrips, burnWindow. A stored themeTuning that still has
// them is read without them.

function tune(cfg) {
    const t = {}
    for (const k in defaults) t[k] = defaults[k]
    try {
        const o = JSON.parse((cfg && cfg.themeTuning) || "{}")
        for (const k in defaults)
            if (k !== "deadDays" && k !== "stickySessions" && typeof o[k] === "number" && isFinite(o[k])) t[k] = o[k]
    } catch (e) {}
    const dd = cfg ? Number(cfg.themeDeadDays) : NaN
    if (isFinite(dd) && dd >= 1) t.deadDays = dd
    const ss = cfg ? Number(cfg.themeStickySessions) : NaN
    if (isFinite(ss) && ss >= 0) t.stickySessions = ss
    t.hotWindow = Math.max(1, Math.round(t.hotWindow))
    t.hotDays = Math.min(t.hotWindow, Math.max(1, Math.round(t.hotDays)))
    t.stayDays = Math.min(t.hotDays, Math.max(1, Math.round(t.stayDays)))
    // The history has to reach back past the dead line and as far again,
    // for the hot day before it, or nothing could ever be called dead.
    // Sessions are fewer than calendar days, so this over-covers.
    t.keepDays = Math.max(t.keepDays, Math.ceil(t.deadDays) * 2, t.window + t.hotWindow)
    return t
}

function median(xs) {
    const a = xs.filter(x => typeof x === "number" && isFinite(x)).sort((p, q) => p - q)
    if (!a.length) return NaN
    const m = Math.floor(a.length / 2)
    return a.length % 2 ? a[m] : (a[m - 1] + a[m]) / 2
}

// Did one member run? `m` is {peak, news, rvol}. Rows stored before
// 2026-10-26 carry neither news nor volume: they are read at `ranPct` and
// pass the volume test, so the first sessions are not thrown away.
function isRunner(m, t) {
    if (!m || !isFinite(m.peak)) return false
    const line = m.news === false ? t.noNewsPct : t.ranPct
    if (m.peak < line) return false
    return !(t.runRvol > 0) || !(typeof m.rvol === "number" && isFinite(m.rvol)) || m.rvol >= t.runRvol
}

// One day's reading for one group, from its members.
//
// `members` is {symbol: {peak, news, rvol, last, at10, shell, fresh}} -- peak
// is the best change on the day seen while the symbol was on the board, which
// is why this has to be accumulated through the session rather than read at
// the close. `last` is its latest change and `at10` its change at 10:00 New
// York time: how much of the peak the runners kept.
function readDay(members, t) {
    const syms = Object.keys(members || {})
    const peaks = syms.map(s => members[s].peak)
    const runners = syms.filter(s => isRunner(members[s], t)).sort((a, b) => members[b].peak - members[a].peak)
    const shells = syms.filter(s => members[s].shell).length
    const fresh = syms.filter(s => members[s].fresh).length
    const top = peaks.length ? Math.max.apply(null, peaks) : NaN
    const med = median(peaks)
    const keep = k => median(runners.map(s => members[s][k] / members[s].peak * 100)
                                    .filter(x => isFinite(x)))
    return {
        n: syms.length,
        ran: runners.length,
        runners: runners.map(s => ({ symbol: s, peak: members[s].peak, news: members[s].news })),
        follow: syms.length ? (100 * runners.length / syms.length) : 0,
        med: med,
        top: top,
        // How far the best member is ahead of the middle one. Early in a theme
        // the second and third names run too; late, only the leader works and
        // this gap opens -- which is exactly when a sympathy play stops paying.
        spread: isFinite(top) && isFinite(med) ? top - med : NaN,
        shells: syms.length ? (100 * shells / syms.length) : 0,
        fresh: syms.length ? (100 * fresh / syms.length) : 0,
        // The runners' gain kept, as a % of their peak (median): now, and at 10:00.
        kept: keep("last"),
        kept10: keep("at10")
    }
}
// A session in which the group had nobody on the board. It still counts:
// it lowers the usual rate and stretches the time since anything ran.
function emptyDay(d) {
    return { d: d || "", n: 0, ran: 0, runners: [], follow: 0, med: NaN, top: NaN, spread: NaN, shells: 0, fresh: 0,
             kept: NaN, kept10: NaN, led: false, syms: [] }
}

// Is the trend across `days` (oldest first) going the wrong way? Compares the
// last reading with the mean of the ones before it, so a single quiet day does
// not call a theme dead.
function falling(days, key) {
    if (days.length < 2) return false
    const last = days[days.length - 1][key]
    const prior = days.slice(0, -1).map(d => d[key]).filter(x => isFinite(x))
    if (!isFinite(last) || !prior.length) return false
    return last < prior.reduce((a, b) => a + b, 0) / prior.length
}
function rising(days, key) {
    if (days.length < 2) return false
    const last = days[days.length - 1][key]
    const prior = days.slice(0, -1).map(d => d[key]).filter(x => isFinite(x))
    if (!isFinite(last) || !prior.length) return false
    return last > prior.reduce((a, b) => a + b, 0) / prior.length
}

// The four ways a theme goes cold, each a direction rather than a level.
// Information for the tooltip only.
function cooling(days) {
    const w = days.filter(d => d.n > 0).slice(-3)
    const out = []
    if (falling(w, "med")) out.push("moves compressing")
    if (rising(w, "shells")) out.push("shells crowding in")
    if (falling(w, "fresh")) out.push("same names repeating")
    if (rising(w, "spread")) out.push("only the leader works")
    return out
}

// The share of sessions in which the group had a runner, over the `window`
// sessions before the record window: its usual rate.
function usual(prior, t) {
    const before = prior.slice(0, Math.max(0, prior.length - (t.hotWindow - 1))).slice(-t.window)
    const rate = before.length ? before.filter(d => d.ran > 0).length / before.length : 0
    return { known: before.length >= t.minHistory, rate: rate, n: before.length }
}
// The record over the last `hotWindow` sessions, `cur` the newest.
function record(prior, cur, t) {
    const win = prior.concat([cur]).slice(-t.hotWindow)
    return { days: win.filter(d => d.ran > 0).length, led: win.filter(d => d.led).length, of: win.length, win: win }
}
// HOT, BUILDING or QUIET for one session -- everything but BURNT, which
// depends on the days around it. `prior[last].hot` must already be set
// (annotate does them in order).
function heat(prior, cur, t) {
    if (!cur) return "quiet"
    const r = record(prior, cur, t)
    const u = usual(prior, t)
    const wasHot = prior.length > 0 && !!prior[prior.length - 1].hot
    if (wasHot && r.days >= t.stayDays) return "hot"
    if (r.days >= t.hotDays && (!u.known || r.days / t.hotWindow >= t.liftX * u.rate)) return "hot"
    if (r.days >= 1) return "building"
    return "quiet"
}
// Marks each stored session `hot` or not, oldest first (each one's mark
// depends on the one before), for staying hot and for BURNT.
function annotate(hist, t) {
    for (let i = 0; i < hist.length; i++)
        if (hist[i].hot === undefined) hist[i].hot = heat(hist.slice(0, i), hist[i], t) === "hot"
    return hist
}
// Calendar days from one "YYYY-MM-DD" to another, NaN if either is missing.
function daysBetween(a, b) {
    if (!a || !b) return NaN
    const x = Date.parse(a + "T12:00:00Z"), y = Date.parse(b + "T12:00:00Z")
    return isFinite(x) && isFinite(y) ? Math.round((y - x) / 86400000) : NaN
}

// The status of one group: {status, n, ran, follow, med, top, lift, expected,
// streak, sinceRun, cooling, why, lastSession, asOf, runDays, led, record}.
// `hist` is that group's finished sessions (oldest first, empty ones
// included), `today` this session's reading or null.
//
// opts.live: `today` is a session still running. Then:
//   - before its first runner, the reading is the last finished session's
//     (a theme hot yesterday does not flash quiet or burnt at 04:00), and
//   - today can raise a status, never burn one: BURNT is judged on finished
//     sessions only.
// With no `today`, the reading is the last finished session's own -- what
// out of hours shows.
function status(hist, today, t, opts) {
    hist = annotate(hist || [], t)
    const live = !!(opts && opts.live)
    let prior, cur, lastSession = false
    if (today && (!live || today.ran > 0)) { prior = hist; cur = today }
    else if (hist.length) { prior = hist.slice(0, -1); cur = hist[hist.length - 1]; lastSession = true }
    else return { status: "quiet", n: 0, ran: 0, follow: 0, med: NaN, top: NaN, shells: 0, fresh: 0,
                  lift: NaN, expected: NaN, baseline: 0, known: false, streak: 0, sinceRun: NaN,
                  cooling: [], why: "", lastSession: false, asOf: "", runDays: 0, led: 0, of: 0,
                  record: [], kept: NaN, kept10: NaN }
    const finished = !(live && cur === today)
    const days = prior.concat([cur])
    const u = usual(prior, t)
    const r = record(prior, cur, t)
    let st = heat(prior, cur, t)

    // "day N": sessions in a row, up to this one, in which something ran.
    let streak = 0
    for (let i = days.length - 1; i >= 0 && days[i].ran > 0; i--) streak++
    // Since the last runner: calendar days when the readings are dated,
    // else sessions.
    let since = NaN
    for (let i = days.length - 1; i >= 0; i--) {
        if (days[i].ran > 0) {
            since = daysBetween(days[i].d, cur.d)
            if (!isFinite(since)) since = days.length - 1 - i
            break
        }
    }
    const wasHot = prior.some(d => d.hot)

    const rec = "runners on " + r.days + " of the last " + r.of + (r.of === 1 ? " session" : " sessions")
              + (r.led ? ", the day's top gainer on " + r.led : "")
    let why = ""
    if (st === "hot") why = rec + (prior.length && prior[prior.length - 1].hot ? " (staying hot)" : "")
    else if (st === "building") why = rec + " (" + t.hotDays + " make it hot)"
    else if (finished && wasHot && isFinite(since) && since >= t.deadDays) {
        st = "burnt"
        why = "nothing has run for " + since + " days"
    } else if (isFinite(since) && since > 0) {
        why = "last ran " + since + (since === 1 ? " day ago" : " days ago")
    }
    return { status: st, n: cur.n, ran: cur.ran, follow: cur.follow,
             med: cur.med, top: cur.top, shells: cur.shells, fresh: cur.fresh,
             lift: u.known && u.rate > 0 ? (r.days / t.hotWindow) / u.rate : NaN,
             expected: u.rate * t.hotWindow, baseline: u.rate * t.hotWindow, known: u.known,
             streak: streak, sinceRun: since, runDays: r.days, led: r.led, of: r.of,
             // The sessions behind the record, newest last: {d, ran, runners, led}.
             record: r.win.map(d => ({ d: d.d, ran: d.ran, runners: d.runners || [], led: !!d.led })),
             kept: cur.kept, kept10: cur.kept10,
             cooling: cooling(days), why: why, lastSession: lastSession, asOf: cur.d || "" }
}

function ran_phrase(d) {
    if (!d) return ""
    return d.ran + " of " + d.n + " ran"
}

// ── colour ───────────────────────────────────────────────────────────────
// Red reads as "down" everywhere else on a trading screen, so the ramp is a
// setting. `heat` is the default: grey, amber, red -- how Matt described it.
// All three keep the same four steps so the shape of the signal does not
// change with the palette.
//
// Checked 2026-10-24 (WCAG 3:1 for icons) on Breeze light #eff0f1, Breeze
// dark #232629 and the dark panel #31363b: quiet, hot and burnt are 3.1:1 or
// better on all three. Amber and lilac are too light for a light background
// as a fill, so a filled glyph draws its lines in `edge` (5:1 on Breeze
// light) and keeps the bright fill for dark ones. Violet's hot and burnt are
// hard to tell apart with red-green colour blindness (CIE76 ΔE 11-14): it is
// labelled as not colour-blind safe in Settings, and burnt is crossed out in
// every ramp so it never depends on colour alone.
var ramps = {
    heat:   { quiet: "#7a828c", building: "#e0a030", hot: "#e24c40", burnt: "#5085ba", edge: { building: "#8a5e00" } },
    market: { quiet: "#7a828c", building: "#e0a030", hot: "#2a9c48", burnt: "#5085ba", edge: { building: "#8a5e00" } },
    violet: { quiet: "#7a828c", building: "#a07ad0", hot: "#ce4cb0", burnt: "#5085ba", edge: { building: "#7650a8" } }
}
// The colour names the legend uses, per ramp.
var rampWords = {
    heat:   { hot: "red", building: "amber" },
    market: { hot: "green", building: "amber" },
    violet: { hot: "magenta", building: "lilac" }
}

function colour(st, rampName) {
    const r = ramps[rampName] || ramps.heat
    return r[st] || r.quiet
}
// The line colour for a filled glyph ("" = the same as the fill).
function edge(st, rampName) {
    const r = ramps[rampName] || ramps.heat
    return (r.edge && r.edge[st]) || ""
}

// A live theme is drawn solid, a quiet or burnt one as an outline, so the
// state reads by shape before the colour is even taken in; burnt is also
// crossed out.
function filled(st) { return st === "hot" || st === "building" }
function crossed(st) { return st === "burnt" }

// What the four colours mean, with the numbers from the live settings. The
// last block of every theme tooltip, and under Icon colours in Settings →
// Themes.
function legend(t, rampName) {
    const w = rampWords[rampName] || rampWords.heat
    return [
        "A runner: up " + t.ranPct + "% on the day (" + t.noNewsPct + "% with no news in 24 hours)"
            + (t.runRvol > 0 ? ", on " + t.runRvol + "× its usual volume or more" : "") + ".",
        "Solid " + w.hot + " — HOT: runners on " + t.hotDays + " of the last " + t.hotWindow
            + " sessions, more often than usual for it; stays hot while they keep turning up.",
        "Solid " + w.building + " — BUILDING: a runner in the last " + t.hotWindow + " sessions, not yet hot.",
        "Blue outline, crossed — BURNT (dead): was hot, and nothing has run for " + t.deadDays + " days.",
        "Grey outline — QUIET: no runner lately. Sectors are always grey.",
        "Before the first runner of the day: the last session's reading."
    ].join("\n")
}

// "SRTM +69% Mon"
function dayName(d) {
    const x = Date.parse(d + "T12:00:00Z")
    return isFinite(x) ? ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][new Date(x).getUTCDay()] : d
}

// The tooltip. States the numbers behind the icon, then what the colours
// mean -- nothing about what to do with them.
function explain(name, s, t, rampName) {
    // Beta until the readings have been checked against weeks of live
    // trading (Matt, 2026-10-24); the label goes when that is done.
    const L = [name + " — " + s.status.toUpperCase() + (s.status === "burnt" ? " (dead)" : "") + " (beta)"]
    if (s.lastSession) L.push("The last session's reading" + (s.asOf ? " (" + s.asOf + ")" : "") + ": nothing has run in this one yet")
    if (s.why) L.push(s.why)
    // The record, newest first: each session's best runners.
    const rec = (s.record || []).slice().reverse().filter(d => d.ran > 0).map(d =>
        dayName(d.d) + (d.led ? " ★" : "") + ": " + d.runners.slice(0, 3).map(r =>
            r.symbol + " +" + Math.round(r.peak) + "%" + (r.news === false ? " (no news)" : "")).join(", ")
            + (d.runners.length > 3 ? " +" + (d.runners.length - 3) + " more" : ""))
    if (rec.length) L.push(rec.join("\n"))
    const bits = []
    if (s.n) bits.push(s.n + (s.n === 1 ? " member" : " members") + (s.lastSession ? "" : " today"))
    if (s.n) bits.push(s.ran + " ran")
    if (isFinite(s.top)) bits.push("best +" + Math.round(s.top) + "%")
    if (bits.length) L.push(bits.join(" · "))
    const b2 = []
    if (isFinite(s.kept10)) b2.push("runners kept " + Math.round(s.kept10) + "% of their peak at 10:00")
    if (isFinite(s.kept)) b2.push(Math.round(s.kept) + "% " + (s.lastSession ? "at the close" : "now"))
    if (s.known) b2.push("usually runners on " + (Math.round(s.expected * 10) / 10) + " of " + t.hotWindow + " sessions")
    if (s.shells) b2.push(Math.round(s.shells) + "% serial issuers")
    if (b2.length) L.push(b2.join(" · "))
    if (s.cooling && s.cooling.length) L.push("Cooling signs (for information): " + s.cooling.join(", "))
    if (t) L.push("", legend(t, rampName))
    return L.join("\n")
}
