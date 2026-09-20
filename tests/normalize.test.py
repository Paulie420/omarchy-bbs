import json
import subprocess
import sys
from pathlib import Path

SCRIPT = Path(__file__).resolve().parent.parent / "bbs-normalize.py"

CSV = (
    "bbsName, bbsSysop, newLogin, TelnetAddress, bbsPort, sshPort, WebAddress, location, Modem, software\n"
    '0xDECAFBAD BBS,,NEW,bbs.decafbad.com,6523,,,"Seattle, WA, USA",,"Synchronet"\n'
    '20 For Beers BBS,paul lee,Desired Handle,20forbeers.com,1337,1338,http://20forbeers.com:1339,"Portland, OR, USA",,"Mystic"\n'
    '4 Wheel Ham BBS,w7jpj,NEW,bbs.4wheelham.com,,2222,http://4wheelham.com,"Littleton, CO, USA",,"Synchronet"\n'
    ",,,,,,,,,\n"  # blank row: must be dropped
    '0xDECAFBAD BBS,,NEW,bbs.decafbad.com,9999,,,"Seattle, WA, USA",,"Synchronet"\n'  # duplicate name: must be dropped
)


def run(csv_text):
    result = subprocess.run(
        [sys.executable, str(SCRIPT)],
        input=csv_text, capture_output=True, text=True, check=True,
    )
    return json.loads(result.stdout)


def test_normalizes_and_defaults_telnet_port():
    rows = run(CSV)
    assert len(rows) == 3, rows

    decafbad = rows[0]
    assert decafbad["name"] == "0xDECAFBAD BBS"
    assert decafbad["host"] == "bbs.decafbad.com"
    assert decafbad["telnetPort"] == 6523
    assert decafbad["sshPort"] is None
    assert decafbad["location"] == "Seattle, WA, USA"
    assert decafbad["country"] == "USA"
    assert decafbad["software"] == "Synchronet"

    beers = rows[1]
    assert beers["sysop"] == "paul lee"
    assert beers["newLoginHint"] == "Desired Handle"
    assert beers["telnetPort"] == 1337
    assert beers["sshPort"] == 1338
    assert beers["webUrl"] == "http://20forbeers.com:1339"

    ham = rows[2]
    # bbsPort was blank -> defaults to the standard telnet port 23.
    assert ham["telnetPort"] == 23
    assert ham["sshPort"] == 2222


def test_strips_control_characters_and_collapses_whitespace():
    csv_text = (
        "bbsName, bbsSysop, newLogin, TelnetAddress, bbsPort, sshPort, WebAddress, location, Modem, software\n"
        '"Messy   Name\nWith\tTabs",,,"host.example",23,,,"City,  ST, USA",,"Custom"\n'
    )
    rows = run(csv_text)
    assert rows[0]["name"] == "Messy Name With Tabs"
    assert rows[0]["country"] == "USA"


def test_rejects_rows_with_no_host():
    csv_text = (
        "bbsName, bbsSysop, newLogin, TelnetAddress, bbsPort, sshPort, WebAddress, location, Modem, software\n"
        "No Host BBS,,,,23,,,,\n"
    )
    assert run(csv_text) == []


if __name__ == "__main__":
    test_normalizes_and_defaults_telnet_port()
    test_strips_control_characters_and_collapses_whitespace()
    test_rejects_rows_with_no_host()
    print("normalize.test.py passed")
