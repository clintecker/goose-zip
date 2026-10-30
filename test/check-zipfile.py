"""List each archive in test/archives with test/example.goose and with
Python's zipfile, and fail on any difference. An archive zipfile refuses
must make example.goose exit 65.

zipfile takes the last end-record signature in the file, so it refuses
comment.zip, whose comment holds one; that archive is checked against
stored.zip, which holds the same entry at the same offsets.

Run from the package root: python3 test/check-zipfile.py
"""
import os
import subprocess
import sys
import zipfile

ARCHIVES = "test/archives"
SAME_AS = {"comment.zip": "stored.zip"}


def ours(path):
    r = subprocess.run(["goose", "run", "test/example.goose", "--", path],
                       capture_output=True)
    return r.returncode, r.stdout.decode("utf-8", "replace")


def theirs(path):
    try:
        infos = zipfile.ZipFile(path).infolist()
    except zipfile.BadZipFile:
        return None
    return "".join("%d %d %d %08x %d %s\n" % (i.compress_type, i.compress_size, i.file_size,
                                               i.CRC, i.header_offset, i.filename)
                   for i in infos)


def main():
    bad = 0
    for name in sorted(os.listdir(ARCHIVES)):
        path = os.path.join(ARCHIVES, name)
        rc, out = ours(path)
        want = theirs(os.path.join(ARCHIVES, SAME_AS.get(name, name)))
        if want is None:
            same = rc == 65
        else:
            same = rc == 0 and out == want
        print("%s %s" % ("same" if same else "DIFF", name))
        if not same:
            print("  ours (exit %d):\n%s  zipfile:\n%s" % (rc, out, want))
            bad += 1
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
