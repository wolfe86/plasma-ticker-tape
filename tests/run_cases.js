// Runs a file of checks against one of the widget's JavaScript libraries.
// Usage: node run_cases.js <library in package/contents/ui> <cases file>
// The library is loaded the way the widget loads it (its QML-only
// `.pragma library` line is dropped); the cases file runs in the same scope
// and calls check(name, ok, detail). Prints {failures: [...], passed: N}.
// Run by test_levels.py and test_options.py; needs Node.js.
const fs = require("fs")
const path = require("path")
const vm = require("vm")

const lib = path.join(__dirname, "..", "package", "contents", "ui", process.argv[2])
const src = fs.readFileSync(lib, "utf8").replace(/^\s*\.pragma library\s*$/m, "")
const cases = fs.readFileSync(path.resolve(process.argv[3]), "utf8")
const failures = []
let passed = 0
const ctx = {
    check: (name, ok, detail) => { if (ok) passed++; else failures.push(name + (detail === undefined ? "" : ": " + JSON.stringify(detail))) },
    console: console
}
vm.createContext(ctx)
vm.runInContext(src + "\n" + cases, ctx)
process.stdout.write(JSON.stringify({ failures: failures, passed: passed }))
