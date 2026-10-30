"""Write the test archives into test/archives with Python's zipfile.

A fixed date and order make the bytes the same on every run:
python3 test/make_archives.py
"""
import io
import os
import zipfile

HERE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "archives")
TEXT = b"".join(b"line %d of the deflated entry\n" % i for i in range(200))


def build(entries, comment=b""):
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w") as z:
        for name, data, method in entries:
            info = zipfile.ZipInfo(name, date_time=(2026, 10, 30, 12, 0, 0))
            info.compress_type = method
            z.writestr(info, data)
        z.comment = comment
    return buf.getvalue()


def main():
    os.makedirs(HERE, exist_ok=True)
    both = build([("a.txt", b"hello\n", zipfile.ZIP_STORED),
                  ("dir/b.txt", TEXT, zipfile.ZIP_DEFLATED),
                  ("dir/", b"", zipfile.ZIP_STORED)])
    out = {
        "stored.zip": build([("a.txt", b"hello\n", zipfile.ZIP_STORED)]),
        "deflated.zip": build([("dir/b.txt", TEXT, zipfile.ZIP_DEFLATED)]),
        "both.zip": both,
        # A comment that holds an end-record signature of its own.
        "comment.zip": build([("a.txt", b"hello\n", zipfile.ZIP_STORED)],
                             comment=b"PK\x05\x06 is not the end"),
        "empty.zip": build([]),
        # Cut inside the central directory, then the end record put back.
        "cut-directory.zip": cut_directory(both),
        "not-zip.bin": b"just some bytes, no end record\n",
    }
    for name, data in out.items():
        with open(os.path.join(HERE, name), "wb") as f:
            f.write(data)


def cut_directory(data):
    end = data.rfind(b"PK\x05\x06")
    cd_at = int.from_bytes(data[end + 16:end + 20], "little")
    return data[:cd_at + 20] + data[end:]


if __name__ == "__main__":
    main()
