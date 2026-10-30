// List a ZIP archive: one line per entry with its method, sizes, CRC-32,
// local header offset and name. test/check-zipfile.py compares this with
// Python's zipfile. Run from the package root:
// goose run test/example.goose [FILE.zip]
import std;
import os;
import zip from "..";

fn main() {
    let a = args();
    let path = if a.len > 1 { a[1] } else { "test/archives/both.zip" };
    var data: u8[>..] = [];
    guard read_file(path, data) else { print("cannot read ", path); exit(66); }
    var z = zip::start();
    var out: u8[>..] = [];
    let ok = zip::open(data, z) && zip::entries(data, z) { e, name =>
        format(out, e.method, " ", e.csize, " ", e.usize, " ");
        format_int(out, e.crc, 16, 8, '0');
        format(out, " ", e.local, " ", name, "\n");
    };
    if !ok { format(out, "byte ", z.err_at, ": "); zip::reason(out, z); out.push('\n'); }
    write_stdout(out);
    if !ok { exit(65); }
}
