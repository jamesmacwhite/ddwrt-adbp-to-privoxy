#!/bin/bash
#
######################################################################
#
#  privoxy-blocklist.sh @ VERSION 152103-1 
#
#  Modified for DD-WRT by: 
#  Simon Sanladerer <simon-at-sanladerer.com>
#  Tested on_ DD-WRT Build BS 25408+ and Kong 23900+
#
#  Additional modifications by:
#  James White <james-at-jmwhite.co.uk>
#
#  Based on Original Script by:
#
#  Author: Andrwe Lord Weber
#  Mail: lord-weber-andrwe<at>renona-studios<dot>org
#  URL: http://andrwe.org/scripting/bash/privoxy-blocklist
#
######################################################################
#
#  Summary: 
#  This script downloads, converts and installs
#  AdblockPlus lists into Privoxy
#
######################################################################

######################################################################
#
#  CHANGELOG:
#  + 141512-1 
#    - Moved to Github
#    - Fixed some Syntax Errors (possibly - tested with shellcheck.net)
#      Please update to the newest Version
#
#  + 141012-1 
#    - Added Domain-Based Blocking
#    - Fixed Regex for Whitelisting (now properly working)
#
#  + 142711-1 
#    - Initial Release 
#    - Fixed Regex from original Script that would 
#      prevent the Filter- and Actionlists from working 
#    - Changed binaries that are used to be compatible 
#      with DD-WRT 25408 and similar
#
######################################################################

######################################################################
#
# script variables and functions
#
######################################################################

# URL of each AdBlock list to download and convert
# Each list must appear on a new line with a backslash denoting a new line
# You can find AdBlock lists at: https://adblockplus.org/en/subscriptions
ADBLOCKLISTS=" \
https://easylist-downloads.adblockplus.org/easylist.txt \
https://easylist-downloads.adblockplus.org/antiadblockfilters.txt"

# If you want to store the custom files on /opt, set this to 1
OPTWARE=0
if [ ${OPTWARE} -eq 1 ] ; then
	ROOTDIR="/opt"
else
	ROOTDIR="/jffs"
fi

# Check if the specified ROOTDIR is actually mounted and available
MOUNTCHECK=$(mount | grep -c " on ${ROOTDIR} ")

if [ "${MOUNTCHECK}" -eq 0 ] ; then
	echo "${ROOTDIR} is not mounted. Please confirm the partition is mounted before continuing"
	exit 1
fi

# Privoxy config dir (default: /jffs/etc/privoxy/)
CONFDIR="${ROOTDIR}/etc/privoxy"
# Script tmp dir
TMPDIR="${ROOTDIR}/tmp/privoxy-blocklist"
TMPNAME=$(basename "${0}")
# Create directory paths if they don't exist
mkdir -p ${CONFDIR}
mkdir -p ${TMPDIR}
# Debug mode, set to 1 to enable
DBG=0

######################################################################
#
# main functions
#
######################################################################

usage()
{
	echo "${TMPNAME} is a script to convert AdBlock Plus lists into Privoxy-lists and install them."
	echo " "
	echo "Options:"
	echo "      -h:    Show this help."
	echo "      -q:    Don't give any output."
	echo "      -v 1:  Enable verbosity 1. Show a little bit more output."
	echo "      -v 2:  Enable verbosity 2. Show a lot more output."
	echo "      -v 3:  Enable verbosity 3. Show all possible output and don't delete temporary files. (For debugging only!!)"
	echo "      -r:    Remove all lists build by this script."
}

# check for dependencies
DEPENDENCIES="curl grep privoxy sed"
for COMMAND in ${DEPENDENCIES}
do
	type -p "${COMMAND}" &>/dev/null && continue || {
		echo "The following dependency is missing: (${COMMAND})."
		exit 1
	}
done

# check whether an instance is already running
[ -e "${TMPDIR}/${TMPNAME}.lock" ] && echo "An instance of ${TMPNAME} is already running. Exit" && exit

debug()
{
	[ ${DBG} -ge "${2}" ] && echo -e "${1}"
}

main()
{
	cpoptions=""
	[ ${DBG} -gt 0 ] && cpoptions="-v"

	for url in ${ADBLOCKLISTS}
	do
		debug "Processing ${url} ...\n" 0
		file="${TMPDIR}/$(basename "${url}")"
		actionfile=${file%\.*}.script.action
		filterfile=${file%\.*}.script.filter
		list=$(basename "${file%\.*}")

		# download list
		debug "Downloading ${url} ..." 0
		curl -s -k "${url}" > "${file}"
		debug ".. downloading done." 0
		[ "$(grep -E '^\[Adblock.*\]$' "${file}")" == "" ] && echo "The list received from ${url} isn't an AdblockPlus list. Skipped" && continue
	
		# convert Adblock Plus list to Privoxy list
		# blacklist of urls
		debug "Creating actionfile for ${list} ..." 1
		echo -e "{ +block{${list}} }" > "${actionfile}"
		sed '/^!.*/d;1,1 d;/^@@.*/d;/\$.*/d;/#/d;s/\./\\./g;s/\?/\\?/g;s/\*/.*/g;s/(/\\(/g;s/)/\\)/g;s/\[/\\[/g;s/\]/\\]/g;s/\^/[\/\&:\?=_]/g;s/^||/\./g;s/^|/^/g;s/|$/\$/g;/|/d' ${file} >> ${actionfile}

		debug "... creating filterfile for ${list} ..." 1
		echo "FILTER: ${list} Tag filter of ${list}" > "${filterfile}"
		# set filter for HTML elements
		sed '/^#/!d;s/^##//g;s/^#\(.*\)\[.*\]\[.*\]*/s@<([a-zA-Z0-9]+)\\s+.*id=.?\1.*>.*<\/\\1>@@g/g;s/^#\(.*\)/s@<([a-zA-Z0-9]+)\\s+.*id=.?\1.*>.*<\/\\1>@@g/g;s/^\.\(.*\)/s@<([a-zA-Z0-9]+)\\s+.*class=.?\1.*>.*<\/\\1>@@g/g;s/^a\[\(.*\)\]/s@<a.*\1.*>.*<\/a>@@g/g;s/^\([a-zA-Z0-9]*\)\.\(.*\)\[.*\]\[.*\]*/s@<\1.*class=.?\2.*>.*<\/\1>@@g/g;s/^\([a-zA-Z0-9]*\)#\(.*\):.*[:[^:]]*[^:]*/s@<\1.*id=.?\2.*>.*<\/\1>@@g/g;s/^\([a-zA-Z0-9]*\)#\(.*\)/s@<\1.*id=.?\2.*>.*<\/\1>@@g/g;s/^\[\([a-zA-Z]*\).=\(.*\)\]/s@\1^=\2>@@g/g;s/\^/[\/\&:\?=_]/g;s/\.\([a-zA-Z0-9]\)/\\.\1/g' ${file} >> ${filterfile}
		debug "... filterfile created - adding filterfile to actionfile ..." 1
		echo "{ +filter{${list}} }" >> "${actionfile}"
		echo "*" >> "${actionfile}"
		debug "... filterfile added ..." 1
		debug "... creating and adding whitlist for urls ..." 1
	
		# install Privoxy actionsfile
		cp ${cpoptions} "${actionfile}" "${CONFDIR}"
		if [ "$(grep "$(basename "${actionfile}")" /tmp/privoxy.conf)" == "" ] 
		then
			debug "\nModifying ${CONFDIR}/config ..." 0
			sed "s/^actionsfile user\.action/actionsfile $(basename "${actionfile}")\nactionsfile user.action/" -i /tmp/privoxy.conf > ${TMPDIR}/config
			debug "... modification done.\n" 0
			debug "Installing new config ..." 0
			cp ${cpoptions} "${TMPDIR}/config" "${CONFDIR}"
			debug "... installation done\n" 0
		fi	
		# install Privoxy filterfile
		cp ${cpoptions} "${filterfile}" "${CONFDIR}"
		if [ "$(grep "$(basename "${filterfile}")" /tmp/privoxy.conf)" == "" ] 
		then
			debug "\nModifying ${CONFDIR}/config ..." 0
			sed "s/^\(#*\)filterfile user\.filter/filterfile $(basename "${filterfile}")\n\1filterfile user.filter/" -i /tmp/privoxy.conf > ${TMPDIR}/config
			debug "... modification done.\n" 0
			debug "Installing new config ..." 0
			cp ${cpoptions} "${TMPDIR}/config" "${CONFDIR}"
			debug "... installation done\n" 0
		fi	
	
		debug "... ${url} installed successfully.\n" 0
	done
}

# create temporary lock file
touch "${TMPDIR}/${TMPNAME}.lock"

# set command to be run on exit
[ ${DBG} -le 2 ] && trap 'rm -fr "${TMPDIR}";exit' INT TERM EXIT

# loop for options
while getopts ":hrqv:" opt
do
	case "${opt}" in 
		"h")
			usage
			exit 0
			;;
		"v")
			DBG="${OPTARG}"
			;;
		"q")
			DBG=-1
			;;
		"r")
			echo "Do you really want to remove all build lists?(y/N)"
			read choice
			[ "${choice}" != "y" ] && exit 0
			rm -rf ${CONFDIR}/*.script.{action,filter} && \
			sed '/^actionsfile .*\.script\.action$/d;/^filterfile .*\.script\.filter$/d' -i /tmp/privoxy.conf && \
			echo "Lists removed." && exit 0
			echo -e "An error occurred while removing the lists.\nPlease have a look into ${CONFDIR} whether there are .script.* files and search for *.script.* in ${CONFDIR}/config."
			exit 1
			;;
		":")
			echo "${TMPNAME}: -${OPTARG} requires an argument" >&2
			exit 1
			;;
	esac
done

debug "URL-List: ${ADBLOCKLISTS}\nPrivoxy-Configdir: ${CONFDIR}\nTemporary directory: ${TMPDIR}" 2
main

# restore default exit command
trap - INT TERM EXIT
[ ${DBG} -lt 2 ] && rm -r ${TMPDIR}
[ ${DBG} -eq 2 ] && rm -vr ${TMPDIR}
exit 0
