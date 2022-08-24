#!/bin/sh
#
# test-update-check.sh

while read -r pkg; do
	output="$(/hostrepo/xbps-src update-check $pkg 2>&1)"
	case "$output" in
		"") : ;; # no updates
		"NO VERSION"*) echo "::error title=Couldn't check updates for $pkg::$output" ;;
		*) echo "::warning title=Update(s) available for $pkg::$output" ;;
	esac
done < /tmp/templates
