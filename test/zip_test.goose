// Every archive in test/archives (made by make_archives.py with Python's
// zipfile), and copies damaged here, with what zip:: must say about each.
// Run from the package root: goose run test/zip_test.goose
import std;
import os;
import zip from "..";

fn read(name: const u8[:]) -> u8[>..] {
    var data: u8[>..] = [];
    assert(read_file(str("test/archives/", name), data));
    return data;
}

// The archive's entries, one line each, or the error.
fn listing(d: const u8[:]) -> u8[>..] {
    var out: u8[>..] = [];
    var z = zip::start();
    var ok = zip::open(d, z);
    if ok {
        ok = zip::entries(d, z) { e, name => format(out, e.index, " ", e.method, " ", e.csize, " ", e.usize, " ", name, "\n"); };
    }
    if !ok { format(out, "byte ", z.err_at, ": "); zip::reason(out, z); }
    return out;
}

// The stored bytes of the entry named `name`, or the error.
fn body_of(d: const u8[:], name: const u8[:]) -> u8[>..] {
    var out: u8[>..] = [];
    var z = zip::start();
    assert(zip::open(d, z));
    let e, found = zip::find(d, z, name);
    if !found { out.append("none"); return out; }
    let b, ok = zip::body(d, e, z);
    if ok { out.append(b); } else { format(out, "byte ", z.err_at, ": "); zip::reason(out, z); }
    return out;
}

fn put32(d: u8[>..]&, at: i64, v: i64) { for k in 4 { d[at + k] = ((v >> (8 * k)) & 0xff) as u8; } }

// The first entry whose name is longer than `n` bytes, stopping the walk.
fn first_longer(d: const u8[:], n: i64) -> i64 {
    var z = zip::start();
    assert(zip::open(d, z));
    zip::entries(d, z) { e, name => if name.len > n { return e.index from first_longer; } };
    return -1;
}

fn main() {
    assert(listing(read("stored.zip")) == "0 0 6 6 a.txt\n");
    assert(body_of(read("stored.zip"), "a.txt") == "hello\n");
    let both = read("both.zip");
    assert(listing(both) == "0 0 6 6 a.txt\n1 8 492 6090 dir/b.txt\n2 0 0 0 dir/\n");
    assert(body_of(both, "dir/b.txt").len == 492);
    assert(body_of(both, "nope") == "none");
    assert(first_longer(both, 5) == 1);
    assert(first_longer(both, 50) == -1);

    // The comment holds an end-record signature; the real record is earlier.
    var z = zip::start();
    let c = read("comment.zip");
    assert(zip::open(c, z) && z.comment_len == 19 && z.entries == 1);
    assert(listing(read("empty.zip")) == "");
    assert(listing(read("not-zip.bin")) == "byte 0: no end of central directory record in the last 65557 bytes");
    assert(listing(read("cut-directory.zip")) == "byte 606: central directory entry 0 runs past the end of the file");

    // A local header without its signature, data past the end, ZIP64.
    var bad = read("stored.zip");
    bad[0] = 'X';
    assert(body_of(bad, "a.txt") == "byte 0: entry 0 has no local header");
    var long = read("stored.zip");
    z = zip::start();
    assert(zip::open(long, z));
    put32(long, z.cd_at + 20, 1000);
    assert(body_of(long, "a.txt") == "byte 35: the data of entry 0 run past the end of the file");
    var big = read("empty.zip");
    big[10] = 0xff;
    big[11] = 0xff;
    assert(listing(big) == "byte 0: ZIP64 archives are not read");
    print("zip_test: ok");
}
