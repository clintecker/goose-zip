# clintecker/goose-zip

ZIP archives for [Goose](https://github.com/aardappel/goose), read in place. A ZIP's directory is at its end, so the package takes the whole file as one view. Entry names and data are views into your bytes: nothing is allocated, nothing is read or written, and decompression is yours (a DEFLATE decoder for method 8).

```goose
import zip from "clintecker/goose-zip@v1";

var z = zip::start();
let ok = zip::open(data, z) && zip::entries(data, z) { e, name =>
    format(out, e.method, " ", e.usize, " ", name, "\n");
};
let e, found = zip::find(data, z, "dir/b.txt");
let stored, read = zip::body(data, e, z);
```

`test/example.goose` lists an archive this way.

## Functions

| Function | What it does |
|---|---|
| `start() -> Zip` | a reader with no archive yet |
| `open(data, z) -> bool` | finds the end-of-central-directory record; fills `z.entries`, `z.cd_at`, `z.cd_size`, `z.end_at` and `z.comment_len` |
| `entries(data, z) { e, name => ... } -> bool` | calls the block for each entry in directory order, with its name as a view into `data`; stop early with `return ... from` |
| `find(data, z, name) -> Entry, bool` | the first entry with that name; false with `z.err_at` at -1 when there is none |
| `body(data, e, z) -> const u8[:], bool` | the entry's bytes as stored, after its local header: the data for `zip::STORED` (0), a DEFLATE stream for `zip::DEFLATE` (8) |
| `reason(out, z)` | what went wrong, as a sentence; `z.err_at` is the file offset |

`e` is a `zip::Entry`: `index`, `at` (its central directory record), `flags`, `method`, `crc`, `csize` (stored size), `usize` (size once decompressed), `local` (its local header) and `name_at`, `name_len`.

The end record is found by searching back from the end, since a comment of up to 65,535 bytes may follow it. A candidate counts only when its comment length ends it at the end of the file, because the comment may hold the signature too.

## Limits

- ZIP64 archives are refused.
- Encryption is not read, and archives are not written.
- The sizes and offsets are the central directory's; the local header is read only for where the data start.

## Errors

`open`, `entries`, `find` and `body` return false, `z.why` says which, and `reason` writes it:

| `z.why` | `reason` |
|---|---|
| `NoEnd` | no end of central directory record in the last 65557 bytes |
| `Zip64` | ZIP64 archives are not read |
| `NotCentral` | central directory entry N has no signature |
| `CentralShort` | central directory entry N runs past the end of the file |
| `NotLocal` | entry N has no local header |
| `DataShort` | the data of entry N run past the end of the file |

## Tests

From the package root: `goose run test/zip_test.goose`, `goose run test/example.goose` and `python3 test/check-zipfile.py`, which compares the listing of every archive with Python's zipfile. `python3 test/make_archives.py` rebuilds `test/archives` with Python's zipfile.
