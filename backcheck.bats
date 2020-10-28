#!/usr/bin/env bats
# shellcheck disable=SC2030 disable=SC2031

setup() {
	backupDir="$(mktemp -d)"
	sourceDir="$(mktemp -d)"
}
teardown() {
	rm -rf "$backupDir" "$sourceDir"
}

function testBackcheck {
	echo 2323 > "$sourceDir"/a-file
	echo $RANDOM > "$sourceDir"/b-file
	rsync -a "$sourceDir"/ "$backupDir"
	echo $RANDOM > "$sourceDir"/source-file-that-is-not-part-of-the-backup.txt
	echo YAY > "$backupDir/a-backup-logfile-which-is-ignored.txt"

	atimeBefore="$(stat --format=%X "$sourceDir/b-file")"
	run "$BATS_TEST_DIRNAME"/backcheck "$@" "$backupDir" "$sourceDir"
	[ "${lines[0]}" == ".._" ] || [ "${lines[0]}" == "._." ] || [ "${lines[0]}" == "_.." ]
	[ "${lines[1]}" == 'Successfully processed 3 files.' ]
	[ "$(echo "$output" | wc -l)" -eq 2 ]
	# Make sure that backcheck doesn't change a file's atime
	[ "$(stat --format=%X "$sourceDir/b-file")" -eq "$atimeBefore" ]

	[ "$status" -eq 0 ]
}

@test "backcheck --help" {
	run "$BATS_TEST_DIRNAME"/backcheck --help

	[[ "$output" =~ Backcheck\ [0-9]+\.[0-9]+\.[0-9]+ ]]
	[[ "$output" =~ Usage:\ backcheck ]]
	[ "$status" -eq 0 ]
}
@test "backcheck" {
	testBackcheck
}
@test "backcheck: Very high timeout" {
	testBackcheck --timeout 12354
}
@test "backcheck: Missmatch (different stat)" {
	echo 2323 > "$sourceDir"/a-file
	echo $RANDOM > "$sourceDir"/b-file
	rsync -a "$sourceDir"/ "$backupDir"

	echo aa > "$backupDir"/b-file
	# Make sure the modified time actually differs
	touch -d'2005-01-01 1:1:1' "$backupDir"/b-file

	run "$BATS_TEST_DIRNAME"/backcheck "$backupDir" "$sourceDir"
	[ "${lines[0]}" == "._" ] || [ "${lines[0]}" == '_.' ]
	[ "${lines[1]}" == 'Successfully processed 2 files.' ]
	[ "$status" -eq 0 ]
}
@test "backcheck: Missmatch (matching stat)" {
	echo 2323 > "$sourceDir"/a-file
	echo aa > "$sourceDir"/b-file
	rsync -a "$sourceDir"/ "$backupDir"
	echo bb > "$backupDir"/b-file

	touch -d'2005-01-01 1:1:1' "$sourceDir"/b-file "$backupDir"/b-file

	run "$BATS_TEST_DIRNAME"/backcheck "$backupDir" "$sourceDir"
	[ "$status" -eq 255 ]
	echo "$output" | grep -F "Checksum missmatch '$backupDir/b-file' (bfcc9da4f2e1d313c63cd0a4ee7604e9) <> '$sourceDir/b-file' (d404401c8c6495b206fc35c95e55a6d5), aborting."
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
	[ "${lines[1]}" == 'Successfully processed 3 files.' ]
	[ "$status" -eq 0 ]
}
@test "backcheck: Strange file names (missmatch)" {
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

	[[ "$output" =~ .*Checksum\ missmatch.*\(8f459eed987d0b1587842fda328ca098\).*\(e06c22e3fafeb40b9556bfd522e2c73a\),\ aborting\. ]]
	[ "$status" -eq 255 ]
}
@test "backcheck: Timeout" {
	local i=0
	while [ "$i" -lt 11 ]; do
			echo "$i" > "$sourceDir"/"$i"
		i=$(((i + 1)))
	done

		rsync -a "$sourceDir"/ "$backupDir"

	timeFile="$(mktemp)"
	fakeDate="$(mktemp)"
	chmod +x "$fakeDate"

	cat > "$fakeDate" <<SCRIPT
#!/bin/bash
time="\$(cat "$timeFile")"
echo \$(((time + 1))) > "$timeFile"
echo \$time
SCRIPT
	date +"%s" > "$timeFile"

	run bwrap \
		--bind / / \
		--dev /dev \
		--bind /tmp /tmp \
		--setenv PATH "/usr/local/bin:$PATH" \
		--tmpfs "/usr/local/bin" \
		--ro-bind "$fakeDate" "/usr/local/bin/date" \
	"$BATS_TEST_DIRNAME"/backcheck --timeout 5 "$backupDir" "$sourceDir"

	[ "${lines[0]}" == "....." ]
	[ "${lines[1]}" == 'Timeout reached, successfully processed 5 files.' ]
	[ "$status" -eq 0 ]

	rm -rf "$timeFile" "$fakeDate"
}
@test "backcheck: md5sum run in parralel" {
	local i=0
	while [ "$i" -lt 6 ]; do
			echo "$i" > "$sourceDir"/"$i"
		i=$(((i + 1)))
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
sleep 0.01
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
	[ "${lines[0]}" == "......" ]

	rm -rf "$fakeMd5sum" "$trackingFileSource" "$trackingFileBackup"
}
@test "backcheck: backup md5sum failure" {
	local i=0
	while [ "$i" -lt 11 ]; do
			echo "$i" > "$sourceDir"/"$i"
		i=$(((i + 1)))
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

	rm -rf "$fakeMd5sum"
}
@test "backcheck: source md5sum failure" {
	local i=0
	while [ "$i" -lt 11 ]; do
			echo "$i" > "$sourceDir"/"$i"
		i=$(((i + 1)))
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

	rm -rf "$fakeMd5sum"
}

