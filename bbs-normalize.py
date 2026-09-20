#!/usr/bin/env python3
"""Normalize a Telnet BBS Guide bbslist.csv into the plugin's JSON shape."""
import csv
import json
import sys

FIELD_LIMIT = 200
MAX_RECORDS = 5000


def clean(value, limit=FIELD_LIMIT):
    if value is None:
        return ""
    return " ".join(str(value).split())[:limit]


def parse_port(value):
    value = clean(value, 6)
    if not value.isdigit():
        return None
    port = int(value)
    return port if 1 <= port <= 65535 else None


def parse_country(location):
    parts = [p.strip() for p in location.split(",") if p.strip()]
    return parts[-1] if parts else ""


def normalize_rows(rows):
    seen = set()
    output = []
    for row in rows:
        name = clean(row.get("bbsName"))
        if not name or name in seen:
            continue
        host = clean(row.get("TelnetAddress"))
        if not host:
            continue
        seen.add(name)
        # The source leaves bbsPort blank for boards on the standard telnet
        # port. Its own EtherTerm dialing directory (dialdirectory.xml)
        # confirms this convention by writing port="23" for exactly those
        # rows, so we default to 23 rather than treating it as "no telnet".
        telnet_port = parse_port(row.get("bbsPort")) or 23
        ssh_port = parse_port(row.get("sshPort"))
        location = clean(row.get("location"))
        output.append({
            "name": name,
            "sysop": clean(row.get("bbsSysop")),
            "newLoginHint": clean(row.get("newLogin")),
            "host": host,
            "telnetPort": telnet_port,
            "sshPort": ssh_port,
            "webUrl": clean(row.get("WebAddress"), 300),
            "location": location,
            "country": parse_country(location),
            "software": clean(row.get("software"), 60),
        })
        if len(output) >= MAX_RECORDS:
            break
    return output


def main():
    reader = csv.DictReader(sys.stdin)
    reader.fieldnames = [name.strip() for name in (reader.fieldnames or [])]
    rows = normalize_rows(reader)
    json.dump(rows, sys.stdout)


if __name__ == "__main__":
    main()
