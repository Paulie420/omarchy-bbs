# paulie420.bbs — Omarchy BBS directory plugin — design

## Goal

A bar-widget + panel plugin for Omarchy that lets users browse, search, and
connect to classic telnet/SSH BBSes (Bulletin Board Systems) from the
desktop, with a curated Best/Great/Good tier surfaced above the full
directory, and a built-in guide to the terminal client software needed to
connect.

## Non-goals (v1)

- No interactive 3D globe. Deferred to a v2 stretch goal. v1 is a
  searchable list/dropdown, matching the UI pattern of this author's other
  plugins (`paulie420.vpn`, `.nas`, `.network`).
- No user voting / ranking backend. Tiering is curated by the plugin author
  only, shipped as static data, updated via plugin releases. No accounts,
  no server, no vote-brigading surface — consistent with every other plugin
  this author has published, all of which are client-only.
- No modification of other apps' config (e.g. SyncTERM's own dial
  directory). Connect is a direct one-shot launch, not a directory sync.

## Data source

[Telnet BBS Guide](https://www.telnetbbsguide.com/) publishes a monthly zip
of all listed BBSes, explicitly intended for redistribution. The plugin
author has direct permission from the site owner to use this data in the
plugin.

- URL pattern: `https://www.telnetbbsguide.com/bbslist/ibbs<MM><YY>.zip`
  (e.g. `ibbs0926.zip` for September 2026).
- Inside the zip, `bbslist.csv` is the parse target — one row per BBS:
  `bbsName, bbsSysop, newLogin, TelnetAddress, bbsPort, sshPort,
  WebAddress, location, Modem, software`.
- `location` is a free-text sysop-entered string (e.g. "Portland, OR,
  USA") — country is derived as the last comma-separated segment.

### Fetch script (`bbs-fetch`, modeled on `radio-fetch` from
`akshar.radio-atlas`)

1. Compute the current month/year, try that zip URL with `curl --fail`.
2. On failure (list not yet published this month, or naming convention
   drifts), fall back to scraping `/lists/download-list/` for the actual
   current download link.
3. Extract `bbslist.csv` only (ignore the bundled NetRunner binary and
   other client-specific dial-directory formats).
4. Parse with Python's `csv` module (required for correctness — the
   `location` field contains quoted commas that naive `awk`/`jq` splitting
   would break on) into normalized JSON.
5. Cache at `~/.cache/omarchy-bbs/list.json`. Refresh monthly in the
   background behind a `flock` lock file, same pattern as
   `refresh_world_cache_in_background` in `radio-fetch`. Serve the
   existing cache immediately; never block the UI on a network fetch.
6. Normalized record shape:
   ```json
   {
     "name": "20 For Beers BBS",
     "sysop": "paul lee",
     "newLoginHint": "Desired Handle",
     "telnetHost": "20forbeers.com",
     "telnetPort": 1337,
     "sshPort": 1338,
     "webUrl": "http://20forbeers.com:1339",
     "location": "Portland, OR, USA",
     "country": "USA",
     "software": "Mystic",
     "tier": null
   }
   ```
   `tier` is populated by a join against `tiers.json` (below), not part of
   the fetched data itself.

## Curation (Best / Great / Good)

Static file, `assets/tiers.json`, maintained by the plugin author and
shipped via normal plugin releases — not touched by the fetch/cache cycle,
so a monthly data refresh never clobbers curation:

```json
{
  "best": ["20 For Beers BBS", "..."],
  "great": ["..."],
  "good": ["..."]
}
```

Lookup key is `bbsName` as it appears in `bbslist.csv` (names are unique in
the source list). No in-plugin authoring UI; the author edits this file
directly and cuts a release. **Open item:** the author will supply the real
seed list separately; this spec ships with an empty/placeholder file so the
data pipeline and UI are not blocked on content collection.

Users get local favorites/pins only (stored client-side, same pattern as
`radio-atlas`'s `~/.local/share/radio-atlas/state.json`) — not a public
vote. No backend, no accounts.

## Plugin structure

Manifest shape follows `akshar.radio-atlas`:

```json
{
  "schemaVersion": 1,
  "id": "paulie420.bbs",
  "kinds": ["bar-widget", "panel"],
  "entryPoints": {
    "panel": "BbsGuide.qml",
    "barWidget": "BarWidget.qml"
  },
  "barWidget": {
    "displayName": "BBS Guide",
    "category": "Utilities",
    "defaultSection": "right"
  }
}
```

- `BarWidget.qml` — bar icon, same `implicitWidth`/`implicitHeight` trap to
  avoid as `omarchy-vpn` hit (a Panel-rooted item with no implicit size
  renders 0×0).
- `BbsGuide.qml` — the panel: search box, tier filter chips (Best / Great /
  Good / All), Protocol filter (Telnet / SSH), Software filter (dropdown —
  many distinct values: Mystic, Synchronet, Spitfire, Image BBS, etc.),
  Country filter (dropdown, derived from `location`). List rows show name,
  location, software, tier badge. Selecting a row opens a detail view:
  sysop, host:port(s), web link, Connect button, Copy-address button.
- A separate "How to Connect" tab/section, static content: SyncTERM (AUR,
  already this machine's daily driver), NetRunner, TERMinator/qodem as
  alternatives; a plain-language telnet-vs-ssh explainer (SSH generally
  requires an existing BBS account; telnet is the historically
  anonymous-friendly default); and how to hand a host/port to whichever
  client the user picks.
- `BbsModel.js` — pure data-shaping helpers (search/filter/tier-join), unit
  tested, mirroring `RadioModel.js`'s role in radio-atlas.

## Connect flow

`syncterm` accepts a URL argument directly (confirmed via `man syncterm`):
`syncterm telnet://host:port` or `syncterm ssh://host:port`. The Connect
button:

1. If `syncterm` is installed, launch it with the constructed URL via
   `omarchy-launch-terminal syncterm <url>` — the same stock helper Omarchy
   uses to open terminal apps (confirmed: it execs
   `xdg-terminal-exec -- "$@"` in the active terminal's cwd), so SyncTERM
   opens correctly regardless of the user's configured terminal emulator.
2. If not installed, fall back to showing the connect string with a
   Copy-address button and a link to the How-to-Connect tab.

No BBS gets special-cased in the UI (including the author's own, 20 For
Beers BBS at `20forbeers.com:1337`) — it appears exactly like any other
entry, tiered on its own merits via `tiers.json`.

## Testing

- `./tests/run` covering `BbsModel.js` (search/filter/tier-join logic) and
  the fetch script's CSV normalization, mirroring radio-atlas's
  `tests/model.test.mjs` pattern.
- `omarchy plugin validate .` and
  `qmllint -I /usr/share/omarchy/shell *.qml` before any push.
- Manual check via `qs -p /usr/share/omarchy/shell ipc call shell
  debugBarGeometry` to confirm the bar widget actually renders (non-zero
  size), per the trap already hit building `omarchy-vpn`.

## Licensing / attribution

Telnet BBS Guide's `info.txt` license text is not fully clear on its own
about redistributing *parsed/reformatted* data (as opposed to the
unaltered zip) — the plugin author has separately obtained direct
permission from the site owner to use this data, so this is resolved.
Attribution to Telnet BBS Guide, with a link back, will be included in the
plugin's README and in-app credits.

## Open items before first public release

1. Author to supply the real Best/Great/Good seed list for `tiers.json`.
