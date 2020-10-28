# Backcheck

Check that the files in a backup directory are readable and identical to the ones in the source directory (if their file size and modified time matches). This can be used to test backups, done by `rsync -a` (or similar). Backcheck can do partial checks (with `--timeout`, checking a random selection of files) or fully test backups.

The most prominent use case for this is occasionally checking a backup, without having to read it entirely.


```
Backcheck 0.0.1
Usage: backcheck [--timeout s] backup-path source-path

Check that the files in backup-path are readable and identical to the ones in source-path.
This can be used to partially (with --timeout, checking a random selection of files) or 
to fully test a backup (done by rsync -a or something similar).

        --timeout               Abort after checking files for at least this many seconds.
```

### Notes
#### Why use `md5sum`, not `cmp`?
`md5sum` can easily be run in parallel (once per file), while `cmp` reads files it compares in an alternating fashion, which doesn't allow using the full available io capacity.

#### Why skip if the file size and modified time matches (and not error)?
To avoid failures for slightly stale backups and because in these cases `rsync` (and similar tools) would also detect the differences easily.
