#!/bin/bash

#  Copyright 2021-2023 eismann@5H+yXYkQHMnwtQDzJB8thVYAAIs
#
#  Licensed under the Apache License, Version 2.0 (the "License");
#  you may not use this file except in compliance with the License.
#  You may obtain a copy of the License at
#
#  http://www.apache.org/licenses/LICENSE-2.0
#
#  Unless required by applicable law or agreed to in writing, software
#  distributed under the License is distributed on an "AS IS" BASIS,
#  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#  See the License for the specific language governing permissions and
#  limitations under the License.

# Some lines were taken from the script 1fichier.sh by SoupeAuLait@Rindexxx

#region Functions

verbosePrint() {
	if [ "$verbose" = true ]; then
        echo "DEBUG: $1" >&2
    fi
}

checkTor() {
	local torPort=""
	local nonTorIP=$(curl -s https://check.torproject.org/api/ip)
	verbosePrint "Non Tor IP: $nonTorIP"

	for port in 9050 9150; do
		verbosePrint "Port: $port"

		local torIP=$(curl -x socks5h://127.0.0.1:$port -s https://check.torproject.org/api/ip)
		verbosePrint "Tor IP: $torIP"

		local isTor=$(echo "$torIP" | jq '.IsTor')
		verbosePrint "Tor active: $isTor"

		if [ "$isTor" = "true" ]; then
			verbosePrint "Tor works"
			torPort="$port"
			break
		fi
	done

	echo $torPort
}

tcurl() {
	if [ "$verbose" = true ]; then (echo $@ >&2); fi

	curl --proxy "socks5h://$torUser:$torPassword@127.0.0.1:$torPort" --connect-timeout 15 --user-agent "Mozilla/5.0 (Windows NT 10.0; rv:109.0) Gecko/20100101 Firefox/115.0" --header "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8" --header "Accept-Language: en-US,en;q=0.5" --header "Accept-Encoding: gzip, deflate, br" --compressed "$@"
}

failedDownload() {
	verbosePrint "Write failed links to file"
	echo "$2" >> "$1/failed.txt"
}

removeTempDir() {
	verbosePrint "Remove temp dir"
	rm --recursive --force "$1"
}

removeCookies() {
	verbosePrint "Remove temp cookies"
	rm --force "$1"
}

cancelDownload() {
	verbosePrint "Download cancelled"
	removeTempDir "$lastTempDir"
	exit 1
}

createDirectory() {
	local directoryPath="$1"

	# Checks if the directory doesn't exist
	if [ ! -d "$directoryPath" ]; then
		# Attempts to create the directory
		# The condition checks the result of the mkdir command
		if ! mkdir -p "$directoryPath"; then
			# If mkdir fails, it prints an error message and exits the script with an error code
			echo "ERROR: Failed to create directory path '$directoryPath'"
			exit 1
		else
			verbosePrint "Created directory '$directoryPath'"
		fi
	else
		verbosePrint "Directory already exists '$directoryPath'"
	fi
}

downloadFile() {
	trap cancelDownload SIGINT SIGTERM

	# Save argument 'URL'
	local url="$1"
	echo "Processing $url"
	echo -n "Search for a circuit without wait time."

	# Save argument 'Output-Path'
	local baseDir="$2"
	# Create directory if not existend
	createDirectory "$baseDir"

	verbosePrint "Function BaseDir: $baseDir"
	
	# Create temp directory for download file
	local tempDir=$(mktemp -d "$baseDir/tmp.XXX")
	lastTempDir=$tempDir

	verbosePrint "Function TempDir: $tempDir"

	# Loop limits
	local maxCount=500
	local count=0

	# Loop global vars
	local filenameRegEx='>Filename :<.*<td class="normal">(.*)</td>.*>Date :<'
	local slotFound="false"
	local alreadyDownloaded="false"

	# Check if download is available, downloading the html page, checking, ...
	# Try $maxCount times
	while [ $count -le $maxCount ]; do
		count=$(($count + 1))
		verbosePrint "===== Inner Loop ====="
		verbosePrint "Count: $count"
		echo -n "."

		# Create random Tor credentials
		torUser="user-$RANDOM"
		torPassword="password-$RANDOM"

		# Create temp file in temp directory for download
		local cookies=$(mktemp "$tempDir/cookies.XXX")
		verbosePrint "Cookies: $cookies"

		# Download html of 1fichier file page
		local downloadPage=$(tcurl --cookie-jar "$cookies" --silent --show-error "$url")
		if [ "$verbose" = true ]; then (echo "$downloadPage" > "$baseDir/downloadPage.html"); fi

		# Find file name in html
		if [[ "$downloadPage" =~ ${filenameRegEx} ]]; then
			# Save first match of regex
			local filename=${BASH_REMATCH[1]}
			verbosePrint "Filename: $filename"

			# Check if file already downloaded
			if [ -e "$baseDir/$filename" ]; then
				alreadyDownloaded="true"
				break
			fi
		fi

		# Check for warning (paid subscription needed)
		grep --extended-regexp --quiet '<span style="color:red">Warning !</span>|<span style="color:red">Attention !</span>' <<< "$downloadPage"
		# Check if matches exist
		if [ ! "$?" = "0" ] ; then
			verbosePrint "No regex match found"
			
			# Check for free download
			local checkSlot=$(grep --only-matching --perl-regexp 'name="adz" value="\K[^"]+' <<< "$downloadPage")
			verbosePrint "Check slot: $checkSlot"
			if [ $checkSlot ]; then
				# Slot found
				echo "Found. Start downloading..."
				slotFound="true"
				break
			else
				# No slot found
				verbosePrint "No slot found"
				removeCookies "$cookies"
			fi
		else
			verbosePrint "Regex match found: $?"

			removeCookies "$cookies"
		fi
	done

	# Check file already exists or slot not found
	if [ "$alreadyDownloaded" = "true" ] || [ "$slotFound" = "false" ]; then
		if [ "$alreadyDownloaded" = "true" ]; then
			echo "Already downloaded. Skipping."
		elif [ "$slotFound" = "false" ]; then
			echo "Unable to get a circuit without wait time after $maxCount tries."
			failedDownload "$baseDir" "$url"
		fi

		# Remove temp directory (including temp cookie file)
		removeTempDir "$tempDir"

		return
	fi

	# Download additional page
	local downloadLinkPage=$(tcurl --location --cookie "$cookies" --cookie-jar "$cookies" --silent --show-error --form "submit=Download" --form "adz=$get_me" "$url")
	# Extract download link from page
	local downloadLink=$(echo "$downloadLinkPage" | grep --after-context=2 '<div style="width:600px;height:80px;margin:auto;text-align:center;vertical-align:middle">' | grep --only-matching --perl-regexp '<a href="\K[^"]+')

	verbosePrint "Download link: $downloadLink"

	# Check for download link
	if [ "$downloadLink" ]; then
		# Download file
		tcurl --insecure --cookie "$cookies" --referer "$url" --output "$tempDir/$filename" "$downloadLink" --remote-header-name --remote-name
		if [ "$?" = "0" ]; then
			# Remove temp cookie file
			removeCookies "$cookies"

			# Check if file already exists
			if [ -e "$tempDir/$filename" ]; then
				# Move file to destination directory
				mv "$tempDir/$filename" "$baseDir/"
			else
				echo "Download failed."
				# Write file for failed links
				failedDownload "$baseDir" "$url"
			fi
		else
			# Write file for failed links
			failedDownload "$baseDir" "$url"
		fi
	else
		echo "Unable to extract download-link."
		# Write file for failed links
		failedDownload "$baseDir" "$url"
	fi

	# Remove temp directory (including temp cookie file)
	removeTempDir "$tempDir"

	trap - SIGINT SIGTERM
}

helpText() {
	echo "Usage:"
	echo "$0 File-With-URLs [Output-Path]"
	echo "or"
	echo "$0 URL [Output-Path]"
}

#endregion


#region Main

# Check for more than two arguments
if [ "$#" -gt 3 ]; then
	echo "ERROR: Too many arguments passed"
	helpText
	exit 1
fi

# Check for first mandatory argument "File-With-URLs" or "URL"
if [ -n "$1" ]; then
	# Set mandatory argument "File-With-URLs" or "URL"
	downloadSource="$1"
else
	echo "ERROR: Mandatory argument is missing"
	helpText
	exit 1
fi

# Check for second optional argument "Output-Path"
if [ -n "$2" ]; then
	# Set optional argument "Output-Path"
	outputPath="$2"
else
	# Set current path if no second argument passed
	outputPath="$(pwd)"
fi

# Set third optional argument "--verbose"
if [ "$3" = "--verbose" ]; then
	verbose=true
else
	verbose=false
fi

verbosePrint "DownloadSource: $downloadSource"
verbosePrint "OutputPath: $outputPath"

# Check for Tor
torPort=$(checkTor)
verbosePrint "TorPort: $torPort"
if [ -z "$torPort" ]; then
	echo "ERROR: Tor is not running!"
	exit 1
fi
echo "Tor is listening on port '$torPort'"

lastTempDir=""
# Check if first argument is direct link
if [[ "$downloadSource" =~ "1fichier.com" ]]; then
	downloadFile "$downloadSource" "$outputPath"
else
	# First argument is text file
	if [ -f "$downloadSource" ]; then
		# Read the file line by line
		while IFS= read -r line || [ -n "$line" ]; do
			downloadFile "$line" "$outputPath"
		done < "$downloadSource"
	else
		echo "ERROR: File '$file' does not exist."
		exit 1
	fi
fi

#endregion
