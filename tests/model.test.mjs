import assert from "node:assert/strict"
import fs from "node:fs"
import path from "node:path"
import vm from "node:vm"
import { fileURLToPath } from "node:url"

const testDir = path.dirname(fileURLToPath(import.meta.url))
let source = fs.readFileSync(path.join(testDir, "..", "BbsModel.js"), "utf8")
source = source.replace(/^\.pragma library\s*\n/, "")
const model = { Array, String, Object }
vm.createContext(model)
vm.runInContext(source, model)

const entries = [
  { name: "20 For Beers BBS", sysop: "paul lee", host: "20forbeers.com",
    telnetPort: 1337, sshPort: 1338, location: "Portland, OR, USA",
    country: "USA", software: "Mystic", tier: null },
  { name: "0xDECAFBAD BBS", sysop: "", host: "bbs.decafbad.com",
    telnetPort: 6523, sshPort: null, location: "Seattle, WA, USA",
    country: "USA", software: "Synchronet", tier: null },
  { name: "84-24", sysop: "Michele Giorgi", host: "telnet.84-24.org",
    telnetPort: 23, sshPort: null, location: "Rimini, , Italy",
    country: "Italy", software: "Custom", tier: null },
]

const tiers = { best: ["20 For Beers BBS"], great: [], good: ["84-24"] }
const joined = model.joinTiers(entries, tiers)
assert.equal(joined.find(e => e.name === "20 For Beers BBS").tier, "best")
assert.equal(joined.find(e => e.name === "84-24").tier, "good")
assert.equal(joined.find(e => e.name === "0xDECAFBAD BBS").tier, null)
// joinTiers must not mutate its input.
assert.equal(entries[0].tier, null)

const sorted = model.sortByTierThenName(joined)
assert.equal(sorted[0].name, "20 For Beers BBS") // best first
assert.equal(sorted[sorted.length - 1].tier, null)

assert.equal(model.filterEntries(joined, { tier: "best" }).length, 1)
assert.equal(model.filterEntries(joined, { protocol: "ssh" }).length, 1)
assert.equal(model.filterEntries(joined, { country: "Italy" }).length, 1)
assert.equal(model.filterEntries(joined, { software: "Mystic" }).length, 1)
assert.equal(model.filterEntries(joined, { query: "decafbad" }).length, 1)
assert.equal(model.filterEntries(joined, { query: "portland" }).length, 1) // matches location
assert.equal(model.filterEntries(joined, { query: "nonexistent" }).length, 0)
assert.equal(model.filterEntries(joined, {}).length, 3)

assert.deepEqual(model.distinctValues(joined, "country"), ["Italy", "USA"])

assert.equal(model.connectUrl(entries[0], "telnet"), "telnet://20forbeers.com:1337")
assert.equal(model.connectUrl(entries[0], "ssh"), "ssh://20forbeers.com:1338")
assert.equal(model.connectUrl(entries[1], "ssh"), "") // no ssh port -> empty

console.log("model.test.mjs passed")
