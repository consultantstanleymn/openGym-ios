#!/usr/bin/env python3
"""
Pull files out of an Apple Xcode.xip without a Mac.

Why this exists: xtool's SDK builder extracts a Darwin SDK from Xcode.xip, and it runs
`cleanUpXcode` afterwards, which deletes everything under Xcode.app/Contents except
Info.plist, version.plist and Developer. The Developer Disk Images live under
Contents/Developer/Platforms/iPhoneOS.platform/DeviceSupport/ — and the "clean up" step also
takes the Developer directory's siblings, so the DDIs are not in the SDK xtool installs. Without
one mounted, `idevicescreenshot` refuses with "Could not start screenshotr service", which is
the whole reason screenshots off an iPhone need this.

Format, established by reading the bytes rather than trusting the reference:

  XAR  ->  exactly two entries, Metadata (389 B, bzip2) and Content
  Content -> PBZX: a 28-byte header, then XZ streams laid end to end
  each stream decompresses to cpio in odc format ("070707")

The classic PBZX header layout does not parse here — length_of_chunk_offset_table reads as 1 and
number_of_chunks as 0 — so this does not use the chunk offset table at all. It chains the streams
through LZMADecompressor.unused_data instead, which needs no header knowledge and cannot
desynchronise: whatever the decompressor did not consume is where the next stream begins. A
naive scan for the XZ magic also fails, because that magic occurs by chance inside compressed
data (it does, at blob offset 7,498,740).

Only the wanted paths are written; everything else is discarded as it streams, so peak disk is
the size of the largest file extracted rather than the size of Xcode.

    scripts/xip-pull.py <Xcode.xip> <path-substring> [<path-substring> ...]
"""

import bz2
import lzma
import os
import re
import struct
import sys
import zlib

XZ_MAGIC = b"\xfd7zXZ\x00"


# ── XAR ─────────────────────────────────────────────────────────────────────────────────────
# The table of contents sits at offset 28 here, not at the end as in a classic XAR, which is
# why libarchive (`unar`, `lsar`) reports "Data is corrupted" on a perfectly good file.

def xar_entries(path):
    """-> {name: (offset, size, encoding)} with offsets absolute in the file."""
    with open(path, "rb") as f:
        magic, hsize, _ver, toc_c, toc_u, _alg = struct.unpack(">4sHHQQI", f.read(28))
        if magic != b"xar!":
            raise SystemExit(f"not an XAR: {magic!r}")
        f.seek(28)
        toc = zlib.decompress(f.read(toc_c), 15)          # raw deflate, not zlib
    heap = 28 + toc_c                                      # TOC immediately precedes the heap
    out = {}
    for m in re.finditer(rb"<file id=\"\d+\">(.*?)</file>", toc, re.S):
        blob = m.group(1)
        name = re.search(rb"<name>(.*?)</name>", blob, re.S).group(1).decode()
        off = int(re.search(rb"<offset>(\d+)</offset>", blob).group(1))
        size = int(re.search(rb"<size>(\d+)</size>", blob).group(1))
        enc = re.search(rb'<data>.*?<encoding style="([^"]+)"', blob, re.S)
        out[name] = (heap + off, size, enc.group(1) if enc else "none")
    return out


# ── cpio (odc) ───────────────────────────────────────────────────────────────────────────
# Fixed-width octal ASCII header. Offsets are relative to the concatenated stream.

CPIO_HDR = 76  # 6+6+6+6+6+6+6+11+6+11


def cpio_entries():
    """Yields (name, filesize, data_offset, mode) over a concatenated odc cpio stream."""
    buf = b""
    base = 0
    while True:
        # A header is 76 bytes; make sure one is buffered, else pull more.
        if len(buf) < CPIO_HDR:
            return
        if buf[:6] != b"070707":
            return
        try:
            namesize = int(buf[59:65], 8)
            filesize = int(buf[65:76], 8)
            mode = int(buf[18:24], 8)
        except ValueError:
            return
        name_start = CPIO_HDR
        name = buf[name_start:name_start + namesize - 1].decode("utf-8", "replace")
        data_at = name_start + namesize
        # Trailer: a header of all zeros, then whatever follows is padding or the next archive.
        if name == "TRAILER!!!":
            return
        yield name, filesize, data_at, mode
        end = data_at + filesize
        # Drop what has been consumed, keeping the remainder for the next entry.
        consumed = end
        if consumed >= len(buf):
            keep = buf[max(0, len(buf) - 32):]
            buf = keep
            base = 0
        else:
            buf = buf[consumed:]
            base = 0
        # if the remainder is short we loop, the top guard pulls more via _feed
        del base


class CpioWalker:
    """Streaming odc cpio parser. Feed() accepts decompressed bytes in any chunking."""

    def __init__(self, on_entry):
        self.buf = b""
        self.on_entry = on_entry
        self.done = False

    def feed(self, data):
        if self.done:
            return
        self.buf += data
        while True:
            if len(self.buf) < CPIO_HDR:
                return
            if self.buf[:6] != b"070707":
                self.done = True
                return
            try:
                namesize = int(self.buf[59:65], 8)
                filesize = int(self.buf[65:76], 8)
            except ValueError:
                self.done = True
                return
            if len(self.buf) < CPIO_HDR + namesize:
                return
            name = self.buf[CPIO_HDR:CPIO_HDR + namesize - 1].decode("utf-8", "replace")
            if name == "TRAILER!!!":
                self.done = True
                return
            total = CPIO_HDR + namesize + filesize
            if len(self.buf) < total:
                return
            body = self.buf[CPIO_HDR + namesize:total]
            self.buf = self.buf[total:]
            self.on_entry(name, body)


# ── drive ─────────────────────────────────────────────────────────────────────────────────

def extract_from_content(path, entry, needles, outdir, max_entries=400):
    off, size, enc = entry
    hits = []

    def on_entry(name, body):
        if any(n in name for n in needles) and body:
            hits.append((name, len(body), body))

    started = False
    # Apple lays several cpio archives end to end inside one PBZX payload. A TRAILER ends one of
    # them, not the scan, so the walker is rebuilt and the stream keeps going — stopping at the
    # first TRAILER walked 12 MB of a 1.9 GB archive and found no DeviceSupport.
    walker = CpioWalker(on_entry)

    def fresh():
        return CpioWalker(on_entry)

    with open(path, "rb") as f:
        f.seek(off)
        remaining = size
        pend = b""
        while remaining > 0:
            read = min(8 << 20, remaining)
            chunk = f.read(read)
            if not chunk:
                break
            remaining -= len(chunk)
            if pend:
                chunk = pend + chunk
            # Chain XZ streams: whatever the decompressor did not use starts the next one.
            while chunk:
                pos = chunk.find(XZ_MAGIC)
                if pos == -1:
                    # Trailing bytes after the last stream: cpio padding, not entries.
                    if started:
                        walker.feed(chunk)
                    chunk = b""
                    break
                if pos:
                    # The gap before the FIRST stream is the PBZX header, not cpio. Feeding it
                    # would put 28 bytes of junk in front of the first cpio record and the walk
                    # would stop on a bad magic at offset 0.
                    if started:
                        walker.feed(chunk[:pos])
                try:
                    dec = lzma.LZMADecompressor(format=lzma.FORMAT_XZ)
                    out = dec.decompress(chunk[pos:])
                except lzma.LZMAError:
                    chunk = chunk[pos + 1:]
                    continue
                walker.feed(out)
                started = True
                rest = dec.unused_data
                if not rest:
                    chunk = b""
                    pend = b""
                    break
                chunk = rest

    os.makedirs(outdir, exist_ok=True)
    written = []
    for name, n, body in hits:
        base = os.path.basename(name)
        target = os.path.join(outdir, base)
        with open(target, "wb") as out:
            out.write(body)
        written.append((name, n, target))
        if len(written) >= max_entries:
            break
    return written


def main():
    if len(sys.argv) < 3:
        raise SystemExit(__doc__)
    xip = sys.argv[1]
    needles = sys.argv[2:]
    outdir = os.environ.get("OUTDIR", os.path.join(os.path.dirname(os.path.abspath(xip)), "ddi"))

    print(f"XAR entries in {xip}:", file=sys.stderr)
    entries = xar_entries(xip)
    for n, (o, s, e) in entries.items():
        print(f"   {n:<10} offset={o:<15,} size={s:<15,} {e}", file=sys.stderr)

    if "Content" not in entries:
        raise SystemExit("no Content entry")

    print("streaming cpio out of the PBZX/XZ payload…", file=sys.stderr)
    written = extract_from_content(xip, entries["Content"], needles, outdir)
    if not written:
        raise SystemExit(f"nothing matched {needles}")
    for name, n, target in written:
        print(f"   {n:>12,}  {name}  ->  {target}", file=sys.stderr)


if __name__ == "__main__":
    main()