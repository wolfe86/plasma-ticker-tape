// Loads package/contents/ui/themes.js the way the widget does (its QML-only
// `.pragma library` line is dropped) and prints what the tests check, as JSON.
// Run by test_glyphs.py; needs Node.js.
const fs = require("fs")
const path = require("path")
const vm = require("vm")

const file = path.join(__dirname, "..", "package", "contents", "ui", "themes.js")
const src = fs.readFileSync(file, "utf8").replace(/^\s*\.pragma library\s*$/m, "")
const ctx = {}
vm.createContext(ctx)
vm.runInContext(src + "\n;this.__api = { glyphs, glyphNames, sectorCatalog, cryptoCatalog, starterThemes, icon, glyphName, classifyCrypto, custom }", ctx)
const api = ctx.__api

const out = {
  glyphs: api.glyphs,
  glyphNames: api.glyphNames,
  sectors: api.sectorCatalog.map(t => ({ id: t.id, glyph: t.glyph })),
  crypto: api.cryptoCatalog.map(t => ({ id: t.id, glyph: t.glyph, cats: t.cats })),
  starters: api.starterThemes.map(t => ({ id: t.id, glyph: t.glyph })),
  checks: {
    iconIsSvgUrl: api.icon("dot", "#ff0000", true, false, "") .startsWith("data:image/svg+xml;utf8,"),
    unknownGlyphFallsBackToDot: api.icon("no-such-glyph", "#ff0000", true, false, "") === api.icon("dot", "#ff0000", true, false, ""),
    glyphNameDefault: api.glyphName({ id: "s-tech", glyph: "chip" }, {}),
    glyphNameOverride: api.glyphName({ id: "s-tech", glyph: "chip" }, { "s-tech": { glyph: "tank" } }),
    glyphNameIgnoresUploadOnly: api.glyphName({ id: "s-tech", glyph: "chip" }, { "s-tech": { icon: "/x.svg" } }),
    classifyGaming: (api.classifyCrypto(["gaming"]) || {}).id,
    classifyNone: api.classifyCrypto(["not-a-category"]),
    customNeedsIcon: api.custom({ id: "s-tech" }, { "s-tech": { glyph: "tank" } }),
  },
}
process.stdout.write(JSON.stringify(out))
