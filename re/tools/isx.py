import sys, struct, os
src, out = sys.argv[1], sys.argv[2]
d = open(src,'rb').read()
n = struct.unpack_from('<H', d, 14)[0]
off = 0x2e
MAGIC = [0x13,0x35,0x86,0x07]
def dec(buf, key, block):
    b = bytearray(buf); kl = len(key)
    for start in range(0, len(b), block or len(b) or 1):
        end = min(len(b), start + (block or len(b)))
        for i in range(start, end):
            x = b[i]; k = key[(i-start) % kl]
            b[i] = (~(k ^ (((x << 4) | (x >> 4)) & 0xff))) & 0xff
    return bytes(b)
for _ in range(n):
    name = d[off:off+260].split(b'\0')[0].decode('latin1')
    flags, x3, flen = struct.unpack_from('<III', d, off+260)
    off += 260 + 12 + 8 + 2 + 30
    data = d[off:off+flen]; off += flen
    key = bytes(c ^ MAGIC[i%4] for i,c in enumerate(name.encode('latin1')))
    if flags & 6:
        data = dec(data, key, 1024 if flags & 4 else 0)
    print(name, hex(flags), flen, data[:4])
    open(os.path.join(out, os.path.basename(name)),'wb').write(data)
