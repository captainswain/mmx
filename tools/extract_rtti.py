#!/usr/bin/env python3
"""Recover MSVC RTTI class names, vtables and method slots from a PE image.

Usage:
    python3 tools/extract_rtti.py meshmixer.exe out_prefix

Writes <out_prefix>_vftables.txt (class -> method RVAs) and
<out_prefix>_classes.txt (class -> method VAs). The parser assumes an x64
MSVC image with RTTI present and no incremental-link thunks.
"""

import collections
import struct
import sys


def parse_sections(data):
    pe = struct.unpack_from("<I", data, 0x3C)[0]
    if data[pe:pe + 4] != b"PE\0\0":
        raise ValueError("not a PE image")
    coff = pe + 4
    nsec = struct.unpack_from("<H", data, coff + 2)[0]
    opt = coff + 20
    magic = struct.unpack_from("<H", data, opt)[0]
    imagebase = (struct.unpack_from("<Q", data, opt + 24)[0]
                 if magic == 0x20B else struct.unpack_from("<I", data, opt + 28)[0])
    secoff = opt + struct.unpack_from("<H", data, coff + 16)[0]
    sections = []
    for i in range(nsec):
        o = secoff + i * 40
        name = data[o:o + 8].rstrip(b"\0").decode("latin1")
        vsize, va, rawsize, rawoff = struct.unpack_from("<IIII", data, o + 8)
        sections.append((name, va, vsize, rawoff, rawsize))
    return imagebase, sections


def rva_to_off(sections, rva):
    for _, va, vsize, rawoff, rawsize in sections:
        if va <= rva < va + max(vsize, rawsize):
            return rawoff + (rva - va)
    return None


def off_to_rva(sections, off):
    for _, va, vsize, rawoff, rawsize in sections:
        if rawoff <= off < rawoff + rawsize:
            return va + (off - rawoff)
    return None


def main(path, prefix):
    data = open(path, "rb").read()
    imagebase, sections = parse_sections(data)
    text = next(s for s in sections if s[0] == ".text")
    tstart, tend = text[1], text[1] + text[2]

    # Complete Object Locators: signature 1, pTypeDescriptor RVA pointing at a
    # TypeDescriptor whose name is a decorated class name.
    cols = {}
    for name, va, vsize, rawoff, rawsize in sections:
        if name not in (".rdata", ".data"):
            continue
        for off in range(rawoff, rawoff + rawsize - 24, 4):
            sig, _, _, ptd, _ = struct.unpack_from("<IIIII", data, off)
            if sig != 1:
                continue
            to = rva_to_off(sections, ptd)
            if to is None:
                continue
            cls = data[to + 16:to + 16 + 200].split(b"\0")[0]
            if cls.startswith(b".?A"):
                cols[imagebase + va + (off - rawoff)] = cls.decode("latin1")

    # Vtables store the COL address in the slot before the first method; a run
    # of at least three text pointers is treated as a vtable.
    methods = collections.defaultdict(set)
    for name, va, vsize, rawoff, rawsize in sections:
        if name not in (".rdata", ".data"):
            continue
        off = rawoff
        end = rawoff + rawsize
        while off + 16 <= end:
            q = struct.unpack_from("<Q", data, off)[0]
            if not (imagebase + tstart <= q < imagebase + tend):
                off += 8
                continue
            start = off
            run = []
            while off + 8 <= end:
                q = struct.unpack_from("<Q", data, off)[0]
                if not (imagebase + tstart <= q < imagebase + tend):
                    break
                run.append(q - imagebase)
                off += 8
            if len(run) >= 3 and start >= rawoff + 8:
                col = struct.unpack_from("<Q", data, start - 8)[0]
                if col in cols:
                    methods[cols[col]].update(run)
            continue

    def clean(n):
        n = n.replace(".?AV", "").replace(".?AU", "")
        if n.endswith("@@"):
            n = n[:-2]
        return n.replace("@", "::")

    rows = sorted(((clean(k), sorted(v)) for k, v in methods.items()),
                  key=lambda kv: -len(kv[1]))
    with open(prefix + "_vftables.txt", "w") as f:
        for cls, addrs in rows:
            f.write("%4d  %s\n" % (len(addrs), cls))
            f.write("      " + " ".join("0x%x" % a for a in addrs) + "\n")
    with open(prefix + "_classes.txt", "w") as f:
        for cls, addrs in rows:
            f.write("%s\n" % cls)
            for a in addrs:
                f.write("  0x%x\n" % (imagebase + a))
    print("%d vtables, %d classes, %d method slots" %
          (len(methods), len(rows), sum(len(a) for _, a in rows)))


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
