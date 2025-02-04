#!/usr/bin/env bash

# This is a Unimus to Git API to export your backups to your Git Repo


# $1 is echo message
function echoGreen(){
	printf "$(date +'%F %H:%M:%S') $1\n" >> $log
	local green='\033[0;32m'
	local reset='\033[0m'
	echo -e "${green}$1${reset}"
}


# $1 is echo message
function echoYellow(){
	printf "WARNING: $(date +'%F %H:%M:%S') $1\n" >> $log
	local yellow='\033[1;33m'
	local reset='\033[0m'
	echo -e "WARNING: ${yellow}$1${reset}"
}


# $1 is echo message
function echoRed(){
	printf "ERROR: $(date +'%F %H:%M:%S') $1\n" >> $log
	local red='\033[0;31m'
	local reset='\033[0m'
	echo -e "ERROR: ${red}$1${reset}"
}


# $1 is $? from the command being checked
# #2 is the error message
function errorCheck(){
	if [ $1 -ne 0 ]; then
		echoRed "$2"
		exit "$1"
	fi
}


# This function will do a get request
# $1 is the api request
function unimusGet(){
	local get_request=$(curl -s -H 'Accept: application/json' -H "Authorization: Bearer $unimus_api_key" "$unimus_server_address/api/v2/$1")
	errorCheck "$?" 'Unable to get data from unimus server'
	echo "$get_request"
}


# Verify's Server is online
function unimusStatusCheck(){
	local get_status=$(unimusGet 'health')
	local status=$(jq -r '.data.status' <<< $get_status)
	errorCheck "$?" 'Unable to peform unimus Status Check'
	echo "$status"
}


# $1 is the device id
# $2 is the date of the backup
# $3 is the base64 encoded backup
# $4 is the backup type
# Decodes and Saves Backup
function saveBackup(){
	local address=${devices[$1]}
	if [ $4 == 'TEXT' ]; then
		local type='txt'
	elif [ $4 == 'BINARY' ]; then
		local type ='bin'
	fi
	base64 -d <<< $3 > "$backup_dir/$address - $1.$type"
}


function getAllDevices(){
	echoGreen 'Getting Device Information'
	for ((page=0; ; page+=1)); do
		local contents=$(unimusGet "devices?page=$page")
		errorCheck "$?" 'Unable to get device data from unimus'
		for((data=0; ; data+=1)); do
			if ( jq -e ".data[$data] | length == 0" <<< $contents) >/dev/null; then
				break
			fi
			local id=$(jq -e -r ".data[$data].id" <<< $contents)
			local address=$(jq -e -r ".data[$data].address" <<< $contents)
			devices[$id]=$address
		done
		if ( jq -e '.data | length == 0' <<< $contents ) >/dev/null; then
			break
		fi
	done
}


function getAllBackups(){
	local backupCount=0
	for key in "${!devices[@]}"; do
		for ((page=0; ; page+=1)); do
			local contents=$(unimusGet "devices/$key/backups?page=$page")
			errorCheck "$?" 'Unable to get all backups from unimus'
			for ((data=0; ; data+=1)); do
				if ( jq -e ".data[$data] | length == 0" <<< $contents) >/dev/null; then
					break
				fi
				local deviceId=$key
				local date="$(jq -e -r ".data[$data].validSince" <<< $contents | { read tme ; date "+%F-%T-%Z" -d "@$tme" ; })"
				local backup=$(jq -e -r ".data[$data].bytes" <<< $contents)
				local type=$(jq -e -r ".data[$data].type" <<< $contents)
				saveBackup "$deviceId" "$date" "$backup" "$type"
				let backupCount++
			done
		if [ $(jq -e '.data | length == 0' <<< $contents) ] >/dev/null; then
				break
		fi
		done
	done
	echoGreen "$backupCount backups exported"
}


# Will Pull down backups and save to Disk
function getLatestBackups(){
	local backupCount
	# Query for latest backups. This will loop through getting every page
	for ((page=0; ; pagae+=1)); do
		local contents=$(unimusGet "devices/backups/latest?page=$page")
		errorCheck "$?" 'Unable to get latest backups from unimus'
		for ((data=0; ; data+=1)); do
			# Breaks if looped through all devices
			if ( jq -e ".data[$data] | length == 0" <<< $contents) >/dev/null; then
				break
			fi
			local deviceId=$(jq -e -r ".data[$data].deviceId" <<< $contents)
			local date=$(jq -e -r ".data[$data].backup.validSince" <<< $contents | { read tme ; date "+%F-%T-%Z" -d "@$tme" ; })
			local backup=$(jq -e -r ".data[$data].backup.bytes" <<< $contents)
			local type=$(jq -e -r ".data[$data].backup.type" <<< $contents)
			saveBackup "$deviceId" "$date" "$backup" "$type"
			let backupCount++
		done

		# Breaks if empty page.
		if [ $(jq -e '.data | length == 0' <<< $contents) ] >/dev/null; then
			break
		fi
	done
	echoGreen "$backupCount backups exported"
}


function pushToGit(){
	cd $backup_dir
	errorCheck "$?" 'Failed to enter backup directory'
	if ! [ "$(git rev-parse --is-inside-work-tree 2>/dev/null)" ]; then
		git init
		git add .
		git commit -m 'Initial Commit'
		case $git_server_protocal in
			ssh)
			ssh-keyscan -H git_server_address >> ~/.ssh/known_hosts
			if [ -z "$git_password" ]; then
				git remote add origin ssh://$git_username@$git_server_address:$git_port/$git_repo_name
				errorCheck "$?" 'Failed to add git repo'
			else
				git remote add origin ssh://$git_username:$git_password@$git_server_address:$git_port/$git_repo_name
				errorCheck "$?" 'Failed to add git repo'
			fi
			;;
			http)
			git remote add origin http://$git_username:$git_password@$git_server_address:$git_port/$git_repo_name
			errorCheck "$?" 'Failed to add git repo'
			;;
			https)
			git remote add origin https://$git_username:$git_password@$git_server_address:$git_port/$git_repo_name
			errorCheck "$?" 'Failed to add git repo'
			;;
			*)
			echoRed 'Invalid setting for git_server_protocal'
			exit 2
			;;
		esac
		git push -u origin $git_branch >> $log
		errorCheck "$?" 'Failed to add branch'
		git push >> $log
		errorCheck "$?" 'Failed to push to git'
	else
		git pull
		errorCheck "$?" 'Failed to pull from backups git repo'
		git add --all
		git commit -m "Unimus Git Extractor $(date +'%b-%d-%y %H:%M')"
		git push
		errorCheck "$?" 'Failed to push to backups git repo'
	fi
	cd $script_dir
}


# We can't pass the variable name in any other way
# $1 is the variable
# $2 is the name
function checkVars(){
	if [ -z "$1" ]; then
		echoRed "$2 is not set in unimus-backup-exporter.env"
		exit 2
	fi
}


function importVariables(){
	set -a # Automatically export all variables
	source unimus-backup-exporter.env
	set +a
	checkVars "$unimus_server_address" 'unimus_server_address'
	checkVars "$unimus_api_key" 'unimus_api_key'
	checkVars "$backup_type" 'backup_type'
	checkVars "$export_type" 'export_type'
	if [ "$export_type" == 'git' ]; then
		checkVars "$git_username" 'git_username'
		# Only Checking for password for http. SSH may or may not require a password
		if [[ "$git_server_protocal" == 'http' || "$git_server_protocal" == 'https' ]]; then
			if [ -z "$git_password" ]; then
				echoRed 'Please Provide a git password'
				exit 2
			fi
		fi
		checkVars "$git_email" 'git_email'
		checkVars "$git_server_protocal" 'git_server_protocal'
		checkVars "$git_server_address" 'git_server_address'
		checkVars "$git_port" 'git_port'
		checkVars "$git_repo_name" 'git_repo_name'
		checkVars "$git_branch" 'git_branch'
	fi
}


function main(){
	SCRIPT_VERSION='1.1.0'

	# Set script directory and working dir for script
	script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd -P)
	cd "$script_dir"
	backup_dir=$script_dir/backups

	# HashTable for all devices
	declare -A devices

	# Create Backup Folder
	if ! [ -d 'backups' ]; then
		mkdir backups
		errorCheck "$?" 'Failed to create backup folder'
	fi

	# Creating a log file
	log="$script_dir/unimus-backup-exporter.log"
	printf 'Log File - ' >> $log
	date +"%F %H:%M:%S" >> $log
	
	git pull >> $log
	errorCheck "$?" 'Failed to pull latest code'

	# Importing variables
	importVariables

	status=$(unimusStatusCheck)
	errorCheck "$?" 'Status check failed'

	if [ $status == 'OK' ]; then
		# Getting All Device Information
		echoGreen 'Getting device data'
		getAllDevices

		# Chooses what type of backup we will do
		case $backup_type in
			latest)
			echoGreen 'Exporting latest backups'
			getLatestBackups
			echoGreen 'Export successful'
			;;
			all)
			echoGreen 'Exporting all backups'
			getAllBackups
			echoGreen 'Export successful'
			;;
		esac

		# Exporting to git
		if [ $export_type == 'git' ]; then
			echoGreen 'Pushing to git'
			pushToGit
			echoGreen 'Push successful'
		fi
	else
		if [ -z $status ]; then
			echoRed 'Unable to connect to unimus server'
			exit 2
		else
			echoRed "Unimus server status: $status"
		fi
	fi
	echoGreen 'Script finished'
}


main
