#!/usr/bin/env bats
# shellcheck disable=SC2030 disable=SC2031

setup() {
	backupDir="$(mktemp -d)"
	sourceDir="$(mktemp -d)"
}
teardown() {
	rm -rf "$backupDir" "$sourceDir"

	# Print last output from bats' run
	# bats will not output anything, if the test succeeded.
	if [ -n "$output" ]; then
		echo "Last \$output:"
		echo "$output"
	fi
}
fileSizeSum() {
	du -bc "$@" | tail -n1 | grep -oP '^[0-9]+'
}

function testBackcheck {
	echo 2323 > "$sourceDir"/a-file
	echo $RANDOM > "$sourceDir"/b-file

	rsync -a "$sourceDir"/ "$backupDir"
	echo $RANDOM > "$sourceDir"/source-file-that-is-not-part-of-the-backup.txt
	echo YAY > "$backupDir/a-backup-logfile-which-is-ignored.txt"

	run "$BATS_TEST_DIRNAME"/backcheck "$@"
	[ "${lines[0]}" == ".._" ] || [ "${lines[0]}" == "._." ] || [ "${lines[0]}" == "_.." ]
	local expectedFileSize
	expectedFileSize="$(fileSizeSum "$sourceDir"/a-file "$sourceDir"/b-file)"
	[[ "${lines[1]}" =~ ^Successfully\ processed\ 3\ files\ \(${expectedFileSize}B\)\.$ ]]
	[ "$(echo "$output" | wc -l)" -eq 2 ]

	[ "$status" -eq 0 ]
}
function testAtime {
	echo $RANDOM > "$sourceDir"/b-file

	rsync -a "$sourceDir"/ "$backupDir"
	atimeBefore="$(stat --format=%x "$sourceDir/b-file")"

	"$BATS_TEST_DIRNAME"/backcheck "$backupDir" "$sourceDir" >/dev/null 2>&1
	# Make sure that backcheck doesn't change a file's atime
	[ "$(stat --format=%x "$sourceDir/b-file")" == "$atimeBefore" ] && return 0
	return 1
}

@test "backcheck --help" {
	run "$BATS_TEST_DIRNAME"/backcheck --help

	[[ "$output" =~ Backcheck\ [0-9]+\.[0-9]+\.[0-9]+ ]]
	[[ "$output" =~ Usage:\ backcheck ]]
	[ "$status" -eq 0 ]
}
@test "backcheck: Too few parameters" {
	run "$BATS_TEST_DIRNAME"/backcheck /var/tmp

	[[ "$output" == "backcheck: missing operands"$'\n'"Try 'backcheck --help' for more information." ]]
	[ "$status" -eq 1 ]
}
@test "backcheck" {
	testBackcheck "$backupDir" "$sourceDir"
}
@test "backcheck: Wrapping works if backcheck is not executable" {
	echo BLAH > "$sourceDir"/FILE
	rsync -a "$sourceDir"/ "$backupDir"

	tmpBackcheck="$(mktemp)"

	cat "$BATS_TEST_DIRNAME"/backcheck > "$tmpBackcheck"
	chmod -x "$tmpBackcheck"

	run bash "$tmpBackcheck" "$backupDir" "$sourceDir"

	[ "$status" -eq 0 ]
	[ "${lines[0]}" == "." ]
	local expectedFileSize
	expectedFileSize="$(fileSizeSum "$sourceDir"/FILE)"
	[[ "${lines[1]}" =~ ^Successfully\ processed\ 1\ files\ \(${expectedFileSize}B\)\.$ ]]

	rm -f "$tmpBackcheck"
}
@test "backcheck: Very high timeout" {
	testBackcheck --timeout 12354 "$backupDir" "$sourceDir"
}
@test "backcheck: Only backup dir given with trailing slash" {
	testBackcheck --timeout 12354 "$backupDir/" "$sourceDir"
}
@test "backcheck: Only source dir given with trailing slash" {
	testBackcheck --timeout 12354 "$backupDir" "$sourceDir/"
}
@test "backcheck: Make sure that backcheck doesn't change a file's atime" {
	# This test is a little unstable, thus passing one out of three is ok,
	# as for unknown reasons atime sometimes changes shortly after file creation!
	status=-1
	if testAtime; then
		status=0
	fi

	if [ "$status" -ne 0 ]; then
		sleep 0.5
		if testAtime; then
			status=0
		fi
	fi
	if [ "$status" -ne 0 ]; then
		sleep 5
		if testAtime; then
			status=0
		fi
	fi
	[ "$status" -eq 0 ]
}
@test "backcheck: Invalid timeout" {
	run "$BATS_TEST_DIRNAME"/backcheck --timeout 1a /var/tmp /var/tmp

	[[ "$output" = 'Invalid argument: Timeout must be an integer.' ]]
	[ "$status" -eq 1 ]
}
@test "backcheck: Invalid argument" {
	run "$BATS_TEST_DIRNAME"/backcheck --banana 2 /var/tmp /var/tmp

	[[ "$output" = 'Unknown argument: --banana' ]]
	[ "$status" -eq 1 ]
}
@test "backcheck: backup dir doesn't exist" {
	run "$BATS_TEST_DIRNAME"/backcheck /ddladf /tmp

	[ "$output" == "Backup directory '/ddladf' doesn't exist, aborting." ]
	[ "$status" -eq 1 ]
}
@test "backcheck: source dir doesn't exist" {
	run "$BATS_TEST_DIRNAME"/backcheck /tmp /dafdfjhk

	[ "$output" == "Source directory '/dafdfjhk' doesn't exist, aborting." ]
	[ "$status" -eq 1 ]
}
@test "backcheck: Size estimate" {
	# Read 5M
	head -c 5242880 /dev/urandom > "$sourceDir"/a-file
	rsync -a "$sourceDir"/ "$backupDir"

	run "$BATS_TEST_DIRNAME"/backcheck "$backupDir" "$sourceDir"

	[ "${lines[0]}" == "." ]
	[[ "${lines[1]}" =~ ^Successfully\ processed\ 1\ files\ \(5\.0MiB\)\.$ ]]
	[ "$status" -eq 0 ]
}
@test "backcheck: Mismatch (different stat)" {
	echo 2323 > "$sourceDir"/a-file
	echo $RANDOM > "$sourceDir"/b-file
	rsync -a "$sourceDir"/ "$backupDir"

	echo aa > "$backupDir"/b-file
	# Make sure the modified time actually differs
	touch -d'2005-01-01 1:1:1' "$backupDir"/b-file

	run "$BATS_TEST_DIRNAME"/backcheck "$backupDir" "$sourceDir"
	[ "${lines[0]}" == "._" ] || [ "${lines[0]}" == '_.' ]
	local expectedFileSize
	expectedFileSize="$(fileSizeSum "$sourceDir"/a-file)"
	[[ "${lines[1]}" =~ ^Successfully\ processed\ 2\ files\ \(${expectedFileSize}B\)\.$ ]]
	[ "$status" -eq 0 ]
}
@test "backcheck --verbose: Mismatch (different stat)" {
	echo 2323 > "$sourceDir"/a-file
	echo 123 > "$sourceDir"/b-file
	rsync -a "$sourceDir"/ "$backupDir"

	echo aa > "$backupDir"/b-file
	# Make sure the modified time actually differs
	touch -d'2005-01-01 1:1:1' "$backupDir"/b-file

	run "$BATS_TEST_DIRNAME"/backcheck --verbose "$backupDir" "$sourceDir"

	echo "$output" | grep -Fq "File size mismatch: '$backupDir/b-file' <> '$sourceDir/b-file'."
	# The final message can be on either the third or fourth line.
	local expectedFileSize
	expectedFileSize="$(fileSizeSum "$sourceDir"/a-file)"
	[[ "${lines[2]}${lines[3]}" =~ Successfully\ processed\ 2\ files\ \(${expectedFileSize}B\)\.$ ]]
	[ "$status" -eq 0 ]
}
@test "backcheck --verbose: Source file does not exist" {
	echo 2323 > "$sourceDir"/a-file
	echo 123 > "$sourceDir"/b-file
	rsync -a "$sourceDir"/ "$backupDir"

	rm "$sourceDir"/b-file

	run "$BATS_TEST_DIRNAME"/backcheck --verbose "$backupDir" "$sourceDir"

	echo "$output" | grep -Fq "File does not exist: '$sourceDir/b-file'."
	# The final message can be on either the third or fourth line.
	local expectedFileSize
	expectedFileSize="$(fileSizeSum "$sourceDir"/a-file)"
	[[ "${lines[2]}${lines[3]}" =~ Successfully\ processed\ 2\ files\ \(${expectedFileSize}B\)\.$ ]]
	[ "$status" -eq 0 ]
}
@test "backcheck --verbose: Backup file does no longer exist" {
	echo 2323 > "$sourceDir"/a-file
	echo 123 > "$sourceDir"/b-file
	rsync -a "$sourceDir"/ "$backupDir"

	fakeFind="$(mktemp)"
	chmod +x "$fakeFind"

	cat > "$fakeFind" <<SCRIPT
#!/bin/bash
/usr/bin/find "\$@"

rm /tmp/rw-backupDir-$$/b-file
SCRIPT

	run bwrap \
		--bind / / \
		--dev /dev \
		--bind /tmp /tmp \
		--bind "$backupDir" /tmp/rw-backupDir-$$ \
		--setenv PATH "/usr/local/bin:$PATH" \
		--tmpfs "/usr/local/bin" \
		--ro-bind "$fakeFind" "/usr/local/bin/find" \
	"$BATS_TEST_DIRNAME"/backcheck --verbose "$backupDir" "$sourceDir"
	echo "$output" | grep -Fq "File does not exist: '$backupDir/b-file'."
	# The final message can be on either the third or fourth line.
	local expectedFileSize
	expectedFileSize="$(fileSizeSum "$sourceDir"/a-file)"
	[[ "${lines[2]}${lines[3]}" =~ Successfully\ processed\ 2\ files\ \(${expectedFileSize}B\)\.$ ]]
	[ "$status" -eq 0 ]

	rm -f "$fakeFind"
	rmdir "/tmp/rw-backupDir-$$" 2>/dev/null
}
@test "backcheck --debug: Mismatch (different stat)" {
	echo 2323 > "$sourceDir"/a-file
	echo AAA > "$sourceDir"/b-file
	rsync -a "$sourceDir"/ "$backupDir"

	echo BBB > "$backupDir"/b-file
	# Make sure the modified time actually differs
	touch -d'2005-01-01 1:1:1' "$backupDir"/b-file

	run "$BATS_TEST_DIRNAME"/backcheck --debug "$backupDir" "$sourceDir"
	echo "$output" | grep -Fq "Checking '$backupDir/b-file' <> '$sourceDir/b-file'."
	echo "$output" | grep -Fq "Checking '$backupDir/a-file' <> '$sourceDir/a-file'."
	# --debug implies --verbose
	echo "$output" | grep -Fq "File modification time mismatch: '$backupDir/b-file' <> '$sourceDir/b-file'."
	local expectedFileSize
	expectedFileSize="$(fileSizeSum "$sourceDir"/a-file)"
	[[ "${lines[5]}" =~ ^Successfully\ processed\ 2\ files\ \(${expectedFileSize}B\)\.$ ]]
	[ "$status" -eq 0 ]
}
@test "backcheck: Mismatch (matching stat)" {
	echo 2323 > "$sourceDir"/a-file
	echo aa > "$sourceDir"/b-file
	rsync -a "$sourceDir"/ "$backupDir"
	echo bb > "$backupDir"/b-file

	touch -d'2005-01-01 1:1:1' "$sourceDir"/b-file "$backupDir"/b-file

	run "$BATS_TEST_DIRNAME"/backcheck "$backupDir" "$sourceDir"
	[ "$status" -eq 255 ]
	echo "$output" | grep -F "Checksum mismatch '$backupDir/b-file' (bfcc9da4f2e1d313c63cd0a4ee7604e9) <> '$sourceDir/b-file' (d404401c8c6495b206fc35c95e55a6d5), aborting."
}
@test "backcheck: Strange file names" {
	local backupDir="$backupDir"
	backupDir="$(echo -e "$backupDir/a\\ha\n[a]{4}((/")"
	mkdir "$backupDir"

	local sourceDir="$sourceDir/äöüßßß$%&!\"343%_#*/"
	mkdir "$sourceDir"

	echo 2323 > "$sourceDir"/a-file
	echo $RANDOM > "$sourceDir"/b-file
	echo dfs1 > "$sourceDir/((((((.[[[5656öüß??d"
	rsync -a "$sourceDir"/ "$backupDir"

	run "$BATS_TEST_DIRNAME"/backcheck "$backupDir" "$sourceDir"
	[ "${lines[0]}" == "..." ]
	local expectedFileSize
	expectedFileSize="$(fileSizeSum "$sourceDir"/a-file "$sourceDir"/b-file "$sourceDir/((((((.[[[5656öüß??d")"
	[[ "${lines[1]}" =~ ^Successfully\ processed\ 3\ files\ \(${expectedFileSize}B\)\.$ ]]
	[ "$status" -eq 0 ]
}
@test "backcheck: Strange file names (mismatch)" {
	local backupDir="$backupDir"
	backupDir="$(echo -e "$backupDir/a\\ha\n[a]{4}((/")"
	mkdir "$backupDir"

	local sourceDir="$sourceDir/äöüßßß$%&!\"343%_#*/"
	mkdir "$sourceDir"

	echo 2323 > "$sourceDir"/a-file
	echo $RANDOM > "$sourceDir"/b-file
	echo dfs1 > "$sourceDir/((((((.[[[5656öüß??d"
	rsync -a "$sourceDir"/ "$backupDir"
	echo dfs2 > "$backupDir/((((((.[[[5656öüß??d"

	touch -d'2005-01-01 1:1:1' "$sourceDir/("* "$backupDir/("*

	run "$BATS_TEST_DIRNAME"/backcheck "$backupDir" "$sourceDir"

	[[ "$output" =~ .*Checksum\ mismatch.*\(8f459eed987d0b1587842fda328ca098\).*\(e06c22e3fafeb40b9556bfd522e2c73a\),\ aborting\. ]]
	[ "$status" -eq 255 ]
}
@test "backcheck: file changed while checking" {
	local i=1
	while [ "$i" -lt 11 ]; do
			echo "$i" > "$sourceDir"/"$i"
		i=$((i + 1))
	done

	rsync -a "$sourceDir"/ "$backupDir"

	fakeMd5sum="$(mktemp)"
	chmod +x "$fakeMd5sum"

	cat > "$fakeMd5sum" <<SCRIPT
#!/bin/bash
if [ "\$1" == "$backupDir/5" ]; then
	touch -d'2005-01-01 1:1:1' "/tmp/rw-sourceDir-$$/5"
	echo "00000000000000000000000000000000 /this/is/ignored"

	exit 1
fi
echo "d41d8cd98f00b204e9800998ecf8427e /this/is/ignored"
SCRIPT

	run bwrap \
		--bind / / \
		--dev /dev \
		--bind /tmp /tmp \
		--bind "$sourceDir" /tmp/rw-sourceDir-$$ \
		--setenv PATH "/usr/local/bin:$PATH" \
		--tmpfs "/usr/local/bin" \
		--ro-bind "$fakeMd5sum" "/usr/local/bin/md5sum" \
	"$BATS_TEST_DIRNAME"/backcheck "$backupDir" "$sourceDir"

	# Should contain 10 dots: 9 for the files and one in the final success message.
	[ "$(echo "$output" | grep -oF '.' | wc -l)" -eq 10 ]
	[ "$(echo "$output" | grep -oF '_' | wc -l)" -eq 1 ]
	[ "$status" -eq 0 ]

	rm -f "$fakeMd5sum"
	rmdir "/tmp/rw-sourceDir-$$" 2>/dev/null
}
@test "backcheck: Timeout" {
	if ! command -v faketime >/dev/null 2>&1; then
		skip "Needs faketime"
	fi

	local i=0
	while [ "$i" -lt 11 ]; do
			echo "$i" > "$sourceDir"/"$i"
		i=$((i + 1))
	done

	rsync -a "$sourceDir"/ "$backupDir"

	fakeMd5sum="$(mktemp)"
	chmod +x "$fakeMd5sum"

	cat > "$fakeMd5sum" <<SCRIPT
#!/bin/bash
sleep 100
echo "d41d8cd98f00b204e9800998ecf8427e /this/is/ignored"
SCRIPT

	# Run with a timeout of 350s which will allow 3 of the above 100s sleeps (but it's far enough away from allowing 2 or 4 to be safe)
	run bwrap \
		--bind / / \
		--dev /dev \
		--bind /tmp /tmp \
		--setenv PATH "/usr/local/bin:$PATH" \
		--tmpfs "/usr/local/bin" \
		--ro-bind "$fakeMd5sum" "/usr/local/bin/md5sum" \
	faketime -f '+0y,x250' "$BATS_TEST_DIRNAME"/backcheck --timeout 250 "$backupDir" "$sourceDir"

	[ "${lines[0]}" == "..." ]
	[[ "${lines[1]}" =~ ^Timeout\ reached,\ successfully\ processed\ 3\ files\ \([0-9]{1,2}B\)\.$ ]]
	[ "$status" -eq 0 ]

	rm -f "$fakeMd5sum"
}
@test "backcheck: Handles SIGTERM" {
	local i=0
	while [ "$i" -lt 3 ]; do
			echo "$i" > "$sourceDir"/"$i"
		i=$((i + 1))
	done

	rsync -a "$sourceDir"/ "$backupDir"

	tmpTmp="$(mktemp -d)"
	fakeMd5sum="$(mktemp)"
	chmod +x "$fakeMd5sum"

	cat > "$fakeMd5sum" <<SCRIPT
#!/bin/bash
sleep 100
echo "d41d8cd98f00b204e9800998ecf8427e /this/is/ignored"
SCRIPT

	run bwrap \
		--bind / / \
		--dev /dev \
		--bind "$tmpTmp" /tmp \
		--bind "$backupDir" "$backupDir" \
		--bind "$sourceDir" "$sourceDir" \
		--setenv PATH "/usr/local/bin:$PATH" \
		--tmpfs "/usr/local/bin" \
		--ro-bind "$fakeMd5sum" "/usr/local/bin/md5sum" \
	timeout 0.5 "$BATS_TEST_DIRNAME"/backcheck "$backupDir" "$sourceDir"

	# Make sure the named pipes have been removed
	[ "$(find "$tmpTmp" -name 'backcheck-*')" == "" ]
	[[ "$output" =~ Successfully\ processed\ 0\ files\ \(0B\)\.$ ]]
	[ "$status" -eq 124 ]

	rm -f "$fakeMd5sum"
	rm -rf "$tmpTmp"
}
@test "backcheck: md5sum run in parallel" {
	local i=0
	while [ "$i" -lt 4 ]; do
			echo "$i" > "$sourceDir"/"$i"
		i=$((i + 1))
	done

	rsync -a "$sourceDir"/ "$backupDir"

	trackingFileSource="$(mktemp)"
	trackingFileBackup="$(mktemp)"
	fakeMd5sum="$(mktemp)"
	chmod +x "$fakeMd5sum"

	cat > "$fakeMd5sum" <<SCRIPT
#!/bin/bash
if [[ "\$1" =~ ^$backupDir ]]; then
	trackingFile="$trackingFileBackup"
else
	trackingFile="$trackingFileSource"
fi
if [ "\$(<"\$trackingFile")" == "active" ]; then
	echo "\$trackingFile should not be active at this point!"
	exit 255
fi
echo -n "active" > "\$trackingFile"
while [ ! "\$(<"$trackingFileBackup")" == "active" ] || [ ! "\$(<"$trackingFileSource")" == "active" ]; do
	# Only continue if both are running side-by-side
	sleep 0.005
done
echo "d41d8cd98f00b204e9800998ecf8427e /this/is/ignored"

# Sleep to make sure both instances noticed each other, before going in-active again
sleep 0.1
(sleep 0.005; echo -n"" > "\$trackingFile") &
SCRIPT

	run timeout 5 bwrap \
		--bind / / \
		--dev /dev \
		--bind /tmp /tmp \
		--setenv PATH "/usr/local/bin:$PATH" \
		--tmpfs "/usr/local/bin" \
		--ro-bind "$fakeMd5sum" "/usr/local/bin/md5sum" \
	"$BATS_TEST_DIRNAME"/backcheck "$backupDir" "$sourceDir"

	[ "$status" -eq 0 ]
	[ "${lines[0]}" == "...." ]

	rm -f "$fakeMd5sum" "$trackingFileSource" "$trackingFileBackup"
}
@test "backcheck: backup md5sum failure" {
	local i=0
	while [ "$i" -lt 11 ]; do
			echo "$i" > "$sourceDir"/"$i"
		i=$((i + 1))
	done

	rsync -a "$sourceDir"/ "$backupDir"

	fakeMd5sum="$(mktemp)"
	chmod +x "$fakeMd5sum"

	cat > "$fakeMd5sum" <<SCRIPT
#!/bin/bash
if [ "\$1" == "$backupDir/5" ]; then
	echo "blah blah IO error blah"
	exit 1
fi
echo "d41d8cd98f00b204e9800998ecf8427e /this/is/ignored"
SCRIPT

	run bwrap \
		--bind / / \
		--dev /dev \
		--bind /tmp /tmp \
		--setenv PATH "/usr/local/bin:$PATH" \
		--tmpfs "/usr/local/bin" \
		--ro-bind "$fakeMd5sum" "/usr/local/bin/md5sum" \
	"$BATS_TEST_DIRNAME"/backcheck "$backupDir" "$sourceDir"

	echo "$output" | grep -qF "Hashing '$backupDir/5' failed (blah blah IO error blah), aborting."
	[ "$status" -eq 255 ]

	rm -f "$fakeMd5sum"
}
@test "backcheck: source md5sum failure" {
	local i=0
	while [ "$i" -lt 11 ]; do
			echo "$i" > "$sourceDir"/"$i"
		i=$((i + 1))
	done

	rsync -a "$sourceDir"/ "$backupDir"

	fakeMd5sum="$(mktemp)"
	chmod +x "$fakeMd5sum"

	cat > "$fakeMd5sum" <<SCRIPT
#!/bin/bash
if [ "\$1" == "$sourceDir/5" ]; then
	echo "blah blah IO error blah"
	exit 1
fi
echo "d41d8cd98f00b204e9800998ecf8427e /this/is/ignored"
SCRIPT

	run bwrap \
		--bind / / \
		--dev /dev \
		--bind /tmp /tmp \
		--setenv PATH "/usr/local/bin:$PATH" \
		--tmpfs "/usr/local/bin" \
		--ro-bind "$fakeMd5sum" "/usr/local/bin/md5sum" \
	"$BATS_TEST_DIRNAME"/backcheck "$backupDir" "$sourceDir"

	# Should contain 13 dots: 10 for the files, two in the error message (see below) and one in the final success message.
	[ "$(echo "$output" | grep -oF '.' | wc -l)" -eq 13 ]
	echo "$output" | grep -qF "Warning: Hashing '$sourceDir/5' failed (blah blah IO error blah), continuing."
	[ "$status" -eq 0 ]

	rm -f "$fakeMd5sum"
}
@test "backcheck: mkfifo failure" {
	touch "$backupDir"/a

	# Use rm for mkfifo here: It will fail a) fail and b) output a nice message to stdout.
	run bwrap \
		--bind / / \
		--dev /dev \
		--bind /tmp /tmp \
		--setenv PATH "/usr/local/bin:$PATH" \
		--tmpfs "/usr/local/bin" \
		--bind /usr/bin/rm /usr/local/bin/mkfifo \
	"$BATS_TEST_DIRNAME"/backcheck "$backupDir" "$sourceDir"

	[[ "$output" =~ ^Could\ not\ create\ named\ pipe\ /tmp/backcheck-[0-9]+-backup-sum,\ aborting.$ ]]
	[ "$status" -eq 1 ]
}
@test "backcheck: Relative backup path" {
	echo 'AHA' > "$sourceDir"/a-file
	rsync -a "$sourceDir"/ "$backupDir"

	cd "$(dirname "$backupDir")"
	run "$BATS_TEST_DIRNAME"/backcheck "$(basename "$backupDir")" "$sourceDir"

	[ "${lines[0]}" == "." ]
	local expectedFileSize
	expectedFileSize="$(fileSizeSum "$sourceDir"/a-file)"
	[[ "${lines[1]}" =~ ^Successfully\ processed\ 1\ files\ \(${expectedFileSize}B\)\.$ ]]
	[ "$status" -eq 0 ]
}
@test "backcheck: Relative source path" {
	echo 'AHA' > "$sourceDir"/a-file
	rsync -a "$sourceDir"/ "$backupDir"

	cd "$(dirname "$sourceDir")"
	run "$BATS_TEST_DIRNAME"/backcheck "$backupDir" "$(basename "$sourceDir")"

	[ "${lines[0]}" == "." ]
	local expectedFileSize
	expectedFileSize="$(fileSizeSum "$sourceDir"/a-file)"
	[[ "${lines[1]}" =~ ^Successfully\ processed\ 1\ files\ \(${expectedFileSize}B\)\.$ ]]
	[ "$status" -eq 0 ]
}
@test "backcheck: Non-bwrap fallback" {
	echo 2323 > "$sourceDir"/a-file
	echo aa > "$sourceDir"/b-file
	rsync -a "$sourceDir"/ "$backupDir"

	run bwrap \
		--bind / / \
		--dev /dev \
		--bind /tmp /tmp \
		--setenv PATH "/usr/local/bin:$PATH" \
		--tmpfs "/usr/local/bin" \
		--ro-bind /usr/bin/false "/usr/local/bin/bwrap" \
	"$BATS_TEST_DIRNAME"/backcheck "$backupDir" "$sourceDir"

	[ "$status" -eq 0 ]
	[ "${lines[0]}" == ".." ]
}
