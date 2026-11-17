#!/usr/bin/env python3
"""PlistBuddy'nin tool/configure_ios.sh'in kullandığı alt kümesinin taklidi.

macOS dışında (Linux CI, geliştirici makinesi) configure_ios.sh'in Info.plist
düzenlemelerini sınamak için kullanılır; gerçek derlemede /usr/libexec/PlistBuddy
çalışır. Desteklenen komutlar: Print, Set, Add, Delete
(-c "<komut> :Yol:0:Anahtar [tür] [değer]"). Hatalarda PlistBuddy gibi
stderr'e yazar ve 1 ile çıkar.

Kullanım: plistbuddy_stub.py -c "<komut>" <dosya.plist>
"""
import plistlib
import shlex
import sys

TYPES = {"string", "bool", "integer", "real", "array", "dict"}


def fail(message):
    sys.stderr.write(message + "\n")
    sys.exit(1)


def parse_path(raw):
    if not raw.startswith(":"):
        fail(f"Unrecognized path: {raw}")
    return [part for part in raw[1:].split(":") if part != ""]


def child(container, key):
    if isinstance(container, list):
        if not key.isdigit() or int(key) >= len(container):
            return None
        return container[int(key)]
    if isinstance(container, dict):
        return container.get(key)
    return None


def resolve(root, parts):
    node = root
    for part in parts:
        node = child(node, part)
        if node is None:
            return None
    return node


def convert(kind, value):
    if kind == "string":
        return value
    if kind == "bool":
        return value.strip().lower() in ("true", "yes", "1")
    if kind == "integer":
        return int(value)
    if kind == "real":
        return float(value)
    if kind == "array":
        return []
    if kind == "dict":
        return {}
    fail(f"Unrecognized Type: {kind}")


def render(node, indent=0):
    pad = "    " * indent
    if isinstance(node, dict):
        lines = ["Dict {"]
        for key, value in node.items():
            lines.append(f"{pad}    {key} = {render(value, indent + 1)}")
        lines.append(pad + "}")
        return "\n".join(lines)
    if isinstance(node, list):
        lines = ["Array {"]
        for value in node:
            lines.append(f"{pad}    {render(value, indent + 1)}")
        lines.append(pad + "}")
        return "\n".join(lines)
    if isinstance(node, bool):
        return "true" if node else "false"
    return str(node)


def main(argv):
    if len(argv) != 4 or argv[1] != "-c":
        fail("Usage: plistbuddy_stub.py -c <command> <file>")
    command, path = argv[2], argv[3]
    try:
        tokens = shlex.split(command)
    except ValueError:
        tokens = command.split()
    if len(tokens) < 2:
        fail(f"Unrecognized command: {command}")
    verb, entry, rest = tokens[0], tokens[1], tokens[2:]

    with open(path, "rb") as handle:
        root = plistlib.load(handle)
    parts = parse_path(entry)
    parent = resolve(root, parts[:-1]) if parts else None
    key = parts[-1] if parts else None
    node = resolve(root, parts)

    if verb == "Print":
        if node is None:
            fail(f'Print: Entry, "{entry}", Does Not Exist')
        print(render(node))
        return
    if verb == "Delete":
        if node is None or parent is None:
            fail(f'Delete: Entry, "{entry}", Does Not Exist')
        if isinstance(parent, list):
            del parent[int(key)]
        else:
            del parent[key]
    elif verb == "Set":
        if node is None or parent is None:
            fail(f'Set: Entry, "{entry}", Does Not Exist')
        if isinstance(node, (list, dict)):
            fail(f'Set: Cannot Perform Set On Containers')
        value = " ".join(rest)
        kind = (
            "bool" if isinstance(node, bool)
            else "integer" if isinstance(node, int)
            else "real" if isinstance(node, float)
            else "string"
        )
        new = convert(kind, value)
        if isinstance(parent, list):
            parent[int(key)] = new
        else:
            parent[key] = new
    elif verb == "Add":
        if not rest or rest[0] not in TYPES:
            fail(f"Add: Unrecognized Type: {rest[0] if rest else ''}")
        if parent is None or not isinstance(parent, (list, dict)):
            fail(f'Add: Entry, "{entry}", Parent Does Not Exist')
        new = convert(rest[0], " ".join(rest[1:]))
        if isinstance(parent, list):
            if not key.isdigit() or int(key) > len(parent):
                fail(f'Add: Entry, "{entry}", Invalid Array Index')
            parent.insert(int(key), new)
        else:
            if key in parent:
                fail(f'Add: ":{key}" Entry Already Exists')
            parent[key] = new
    else:
        fail(f"Unrecognized command: {verb}")

    with open(path, "wb") as handle:
        plistlib.dump(root, handle, fmt=plistlib.FMT_XML, sort_keys=False)


if __name__ == "__main__":
    main(sys.argv)
