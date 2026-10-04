#!/usr/bin/env python3
"""Builds the wallpaper-store fixtures from the real one checked in beside it.

wallpaper-store-livepaper.plist is a copy of a real store (README.md); this
script never reads the store on the Mac it runs on. It writes:

- wallpaper-store-aerial.plist: the same store before Livepaper, its two
  Desktop entries naming the Aerial its Idle entries name.
- wallpaper-store-idle-only.plist: the same store with no Desktop entry.
- wallpaper-store-spaces.plist: 24 Desktop entries across 11 Spaces, built in
  the real tree's shape from the real entries and image choices whose files
  are placeholders.

Every output is a binary property list, as the real store is. Run it from
anywhere: python3 make-stores.py
"""

import copy
import datetime
import os
import plistlib
import uuid

HERE = os.path.dirname(os.path.abspath(__file__))
NAMESPACE = uuid.UUID("6f1d3c52-7a0e-4a8e-9a55-2d7c3e5b9a10")


def load(name):
    with open(os.path.join(HERE, name), "rb") as file:
        return plistlib.load(file)


def save(name, tree):
    with open(os.path.join(HERE, name), "wb") as file:
        plistlib.dump(tree, file, fmt=plistlib.FMT_BINARY, sort_keys=True)


def fixed_uuid(name):
    return str(uuid.uuid5(NAMESPACE, name)).upper()


def at(day, hour, minute=0, second=0):
    # plistlib writes a naive datetime as UTC.
    return datetime.datetime(2026, 9, day, hour, minute, second)


REAL = load("wallpaper-store-livepaper.plist")
AERIAL_IDLE = REAL["AllSpacesAndDisplays"]["Idle"]


def aerial(last_set, last_use):
    """A Desktop entry naming the Aerial the real store's Idle entries name, in their form."""
    return {"Content": copy.deepcopy(AERIAL_IDLE["Content"]), "LastSet": last_set, "LastUse": last_use}


def image(url, last_set, last_use):
    """A Desktop entry naming a still. The two blobs are stand-ins: the edit carries them unread."""
    configuration = plistlib.dumps({"type": "imageFile", "url": {"relative": url}}, fmt=plistlib.FMT_BINARY)
    options = plistlib.dumps({"values": {}}, fmt=plistlib.FMT_BINARY)
    choice = {"Configuration": configuration, "Files": [{"relative": url}], "Provider": "com.apple.wallpaper.choice.image"}
    return {
        "Content": {"Choices": [choice], "EncodedOptionValues": options, "Shuffle": "$null"},
        "LastSet": last_set,
        "LastUse": last_use,
    }


def place(desktop, idle=None):
    node = {"Desktop": desktop, "Type": "individual"}
    if idle is not None:
        node["Idle"] = idle
    return node


# Before Livepaper: what Wallper had left on this Mac,
# every Desktop entry naming its Aerial, set on 2026-09-21 at 19:15:04Z and last used the next morning.
before = copy.deepcopy(REAL)
for name in ("SystemDefault", "AllSpacesAndDisplays"):
    before[name]["Desktop"] = aerial(at(21, 19, 15, 4), at(22, 10, 27, 10))
save("wallpaper-store-aerial.plist", before)

idle_only = copy.deepcopy(REAL)
for name in ("SystemDefault", "AllSpacesAndDisplays"):
    del idle_only[name]["Desktop"]
save("wallpaper-store-idle-only.plist", idle_only)

# Placeholders, not anybody's files: two of macOS's own pictures and one under a made-up user.
STILLS = [
    "file:///System/Library/Desktop%20Pictures/Solid%20Colors/Cyan.png",
    "file:///System/Library/Desktop%20Pictures/iMac%20Blue.heic",
    "file:///Users/someone/Pictures/Wallpapers/placeholder.heic",
]
display = fixed_uuid("display-1")
spaces = {}
for number in range(1, 12):
    set_on = at(10 + number % 7, 8 + number)
    used_on = at(23, 9, number)
    by_display = {display: place(image(STILLS[number % 3], set_on, used_on))}
    if number == 11:
        # A Space whose only wallpaper is on its display.
        spaces[fixed_uuid(f"space-{number}")] = {"Displays": by_display}
        continue
    default = aerial(set_on, used_on) if number % 2 else image(STILLS[(number + 1) % 3], set_on, used_on)
    idle = copy.deepcopy(AERIAL_IDLE) if number in (3, 7) else None
    spaces[fixed_uuid(f"space-{number}")] = {"Default": place(default, idle), "Displays": by_display}

many = {
    "SystemDefault": copy.deepcopy(before["SystemDefault"]),
    "AllSpacesAndDisplays": copy.deepcopy(before["AllSpacesAndDisplays"]),
    "Displays": {display: place(image(STILLS[0], at(9, 12), at(23, 9)))},
    "Spaces": spaces,
}
save("wallpaper-store-spaces.plist", many)
