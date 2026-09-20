.pragma library

function tierRank(tier) {
  if (tier === "best") return 3
  if (tier === "great") return 2
  if (tier === "good") return 1
  return 0
}

function joinTiers(entries, tiers) {
  var lookup = {}
  var groups = tiers || {}
  var tierNames = ["best", "great", "good"]
  for (var t = 0; t < tierNames.length; t++) {
    var tierName = tierNames[t]
    var names = Array.isArray(groups[tierName]) ? groups[tierName] : []
    for (var n = 0; n < names.length; n++) lookup["$" + names[n]] = tierName
  }

  var output = []
  for (var i = 0; i < entries.length; i++) {
    var entry = entries[i]
    var tier = lookup["$" + entry.name] || null
    if (tier === entry.tier) {
      output.push(entry)
      continue
    }
    var copy = {}
    for (var key in entry) copy[key] = entry[key]
    copy.tier = tier
    output.push(copy)
  }
  return output
}

function matchesQuery(entry, query) {
  if (!query) return true
  var fields = [entry.name, entry.sysop, entry.software, entry.location, entry.country]
  for (var i = 0; i < fields.length; i++) {
    if (String(fields[i] || "").toLowerCase().indexOf(query) >= 0) return true
  }
  return false
}

function matchesProtocol(entry, protocol) {
  if (!protocol || protocol === "all") return true
  if (protocol === "telnet") return entry.telnetPort !== null && entry.telnetPort !== undefined
  if (protocol === "ssh") return entry.sshPort !== null && entry.sshPort !== undefined
  return true
}

function filterEntries(entries, filters) {
  var opts = filters || {}
  var query = String(opts.query || "").trim().toLowerCase()
  var tier = opts.tier || "all"
  var protocol = opts.protocol || "all"
  var software = opts.software || "all"
  var country = opts.country || "all"

  var output = []
  for (var i = 0; i < entries.length; i++) {
    var entry = entries[i]
    if (tier !== "all" && entry.tier !== tier) continue
    if (software !== "all" && entry.software !== software) continue
    if (country !== "all" && entry.country !== country) continue
    if (!matchesProtocol(entry, protocol)) continue
    if (!matchesQuery(entry, query)) continue
    output.push(entry)
  }
  return output
}

function sortByTierThenName(entries) {
  var output = entries.slice()
  output.sort(function (a, b) {
    var rankDiff = tierRank(b.tier) - tierRank(a.tier)
    if (rankDiff !== 0) return rankDiff
    return a.name < b.name ? -1 : a.name > b.name ? 1 : 0
  })
  return output
}

function distinctValues(entries, key) {
  var seen = {}
  var output = new Array()
  for (var i = 0; i < entries.length; i++) {
    var value = entries[i][key]
    if (!value || seen[value]) continue
    seen[value] = true
    output.push(value)
  }
  output.sort()
  return output
}

function connectUrl(entry, protocol) {
  if (!entry || !entry.host) return ""
  if (protocol === "ssh") return entry.sshPort ? "ssh://" + entry.host + ":" + entry.sshPort : ""
  return entry.telnetPort ? "telnet://" + entry.host + ":" + entry.telnetPort : ""
}
