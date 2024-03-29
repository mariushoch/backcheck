# Backcheck

Check that the files in a backup directory are readable and identical to the ones in the source directory (if their file size and modified time matches). This can be used to test backups, done by `rsync -a` (or similar). Backcheck can do partial checks (with `--timeout`, checking a random selection of files) or fully test backups.

The most prominent use case for this is occasionally checking a backup, without having to read it entirely.


```
Backcheck 1.4.0
Usage: backcheck [--timeout s] [--size-only] [--verbose|--debug] backup-path source-path

Check that the files in backup-path are readable and identical to the ones in source-path.
This can be used to partially (with --timeout, checking a random selection of files) or 
to fully test a backup (done by rsync -a or something similar).

        --timeout               Abort after checking files for at least this many seconds.
        --size-only             Only skip files that mismatch in size (ignoring differing mtimes).
        --verbose               More verbose output (shows details when a file is skipped).
        --debug                 Very verbose output (shows details about all files processed).
```

### Notes
#### Why use `md5sum`, not `cmp`?
`md5sum` can easily be run in parallel (once per file), while `cmp` reads files it compares in an alternating fashion, which doesn't allow using the full available io capacity.

#### Why skip if the file size and modified time matches (and not error)?
To avoid failures for slightly stale backups and because in these cases `rsync` (and similar tools) would also detect the differences easily.

## Changelog
### 1.4.0 (2024-03-27)
* Improved performance by piping `md5sum` output to cat instead of using subshells.
* Reverted "Improve performance especially for small files, by running stat only after md5sum is already running" as it was causing false negatives.

### 1.3.0 (2023-10-26)
* Calculate the exact size of the files tested instead of relying on `rchar`.
* Improve performance especially for small files, by running stat only after md5sum is already running

### 1.2.4 (2023-10-25)
* Made the file path handling more robust
* Made the size estimates a little less inaccurate

### 1.2.3 (2021-11-01)
* Fixed handling relative source or target dir
* Nicer error message when missing source or backup dir
