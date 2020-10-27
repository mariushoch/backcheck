# Backcheck

Check that the files in a backup directory are readable and identical to the ones in the source directory (if their file size and modified time matches). This can be used to test backups, done by `rsync -a` (or similar). Backcheck can do partial checks (with `--timeout`, checking a random selection of files) or fully test backups.


```
Backcheck 0.0.1
Usage: backcheck [--timeout s] backup-path source-path

Check that the files in backup-path are readable and identical to the ones in source-path.
This can be used to partially (with --timeout, checking a random selection of files) or 
to fully test a backup (done by rsync -a or something similar).

        --timeout               Abort after checking files for at least this many seconds.
```