// ZIP archives read in place from the whole file: the end record, each
// central directory entry, and an entry's bytes as stored. ZIP is read from
// its end, so it takes the file as one view instead of pieces. Names and
// data are views into the caller's bytes: nothing is allocated, nothing is
// read or written, and decompression is the caller's (goose-inflate for
// method 8).
namespace zip;
import std;
import binary;

let STORED = 0;
let DEFLATE = 8;

// The end record is 22 bytes and a comment of up to 65,535, so it starts
// in the file's last END_MAX bytes.
let END_MAX = 22 + 65535;

enum Why { None, NoEnd, Zip64, NotCentral, CentralShort, NotLocal, DataShort }

struct Zip {
    entries: i64, cd_at: i64, cd_size: i64,    // from the end record
    end_at: i64, comment_len: i64,
    err_at: i64, why: Why, err_a: i64,         // err_a: the entry's index
}

struct Entry {
    index: i64,
    at: i64, next: i64,                         // its central directory record, and the byte after it
    flags: i64, method: i64, crc: i64, csize: i64, usize: i64,
    local: i64,                                 // its local header
    name_at: i64, name_len: i64,
}

fn start() -> Zip {
    return Zip { entries: 0, cd_at: 0, cd_size: 0, end_at: -1, comment_len: 0, err_at: -1, why: Why.None, err_a: 0 };
}

fn fail(z: Zip&, at: i64, why: Why, a: i64) -> bool {
    z.err_at = at;
    z.why = why;
    z.err_a = a;
    return false;
}

fn reason(out: u8[>..]&, z: Zip&) {
    match z.why {
        None => {},
        NoEnd => format(out, "no end of central directory record in the last ", END_MAX, " bytes"),
        Zip64 => out.append("ZIP64 archives are not read"),
        NotCentral => format(out, "central directory entry ", z.err_a, " has no signature"),
        CentralShort => format(out, "central directory entry ", z.err_a, " runs past the end of the file"),
        NotLocal => format(out, "entry ", z.err_a, " has no local header"),
        DataShort => format(out, "the data of entry ", z.err_a, " run past the end of the file"),
    }
}

// Callers check the bounds first, so these reads are in range.
fn le16(d: const u8[:], at: i64) -> i64 { let v, ok = binary::read_u16le(d, at); return v; }
fn le32(d: const u8[:], at: i64) -> i64 { let v, ok = binary::read_u32le(d, at); return v; }

// An end record at `at`: the signature, and a comment length that ends it
// at the end of the file, as the comment may hold the signature too.
fn is_end(d: const u8[:], at: i64) -> bool { le32(d, at) == 0x06054b50 && at + 22 + le16(d, at + 20) == d.len }

// Find the end record, searched from the end of the file.
fn open(d: const u8[:], z: Zip&) -> bool {
    let stop = max(0, d.len - END_MAX);
    var at = d.len - 22;
    while at >= stop && !is_end(d, at) { at--; }
    guard at >= stop else { return fail(z, stop, Why.NoEnd, 0); }
    z.end_at = at;
    z.entries = le16(d, at + 10);
    z.cd_size = le32(d, at + 12);
    z.cd_at = le32(d, at + 16);
    z.comment_len = le16(d, at + 20);
    if z.entries == 0xffff || z.cd_at == 0xffffffff { return fail(z, at, Why.Zip64, 0); }
    return true;
}

// The central directory record of entry `i` at `at`, into `e`.
fn read_entry(d: const u8[:], z: Zip&, i: i64, at: i64, e: Entry&) -> bool {
    guard at + 46 <= d.len else { return fail(z, at, Why.CentralShort, i); }
    guard le32(d, at) == 0x02014b50 else { return fail(z, at, Why.NotCentral, i); }
    e.name_len = le16(d, at + 28);
    e.next = at + 46 + e.name_len + le16(d, at + 30) + le16(d, at + 32);
    guard e.next <= d.len else { return fail(z, at, Why.CentralShort, i); }
    e.index = i;
    e.at = at;
    e.flags = le16(d, at + 8);
    e.method = le16(d, at + 10);
    e.crc = le32(d, at + 16);
    e.csize = le32(d, at + 20);
    e.usize = le32(d, at + 24);
    e.local = le32(d, at + 42);
    e.name_at = at + 46;
    return true;
}

// Each entry in directory order, with its name as a view into `d`; stop
// early with `return ... from`. False, with err_at, on a damaged directory.
fn entries<F>(d: const u8[:], z: Zip&) -> bool {
    var e = Entry { .. };
    var at = z.cd_at;
    for i in z.entries {
        guard read_entry(d, z, i, at, e) else { return false; }
        F(e, d[e.name_at..e.name_at + e.name_len]);
        at = e.next;
    }
    return true;
}

// The first entry named `name`. False with why None when there is none.
fn find(d: const u8[:], z: Zip&, name: const u8[:]) -> Entry, bool {
    entries(d, z) { e, n => if n == name { return e, true from find; } };
    return Entry { .. }, false;
}

// Entry `e`'s bytes as stored, after its local header: the data for
// STORED, a DEFLATE stream for DEFLATE.
fn body(d: const u8[:], e: Entry, z: Zip&) -> const u8[:], bool {
    guard e.local + 30 <= d.len && le32(d, e.local) == 0x04034b50 else { return "", fail(z, e.local, Why.NotLocal, e.index); }
    let at = e.local + 30 + le16(d, e.local + 26) + le16(d, e.local + 28);
    guard at + e.csize <= d.len else { return "", fail(z, at, Why.DataShort, e.index); }
    return d[at..at + e.csize], true;
}
