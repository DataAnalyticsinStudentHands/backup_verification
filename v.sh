#!/bin/bash

###########################################################
# Automatic Backup Verification Script
# for The Honors College IT - The University of Houston
# @author  Max Ciotti
# @date    7 September 2016
# @license MIT
###########################################################

# http://stackoverflow.com/questions/5566310/
# http://stackoverflow.com/questions/10929453/

# TODO: Ignore cloud storage (Dropbox, Google Drive) in backup script
# TODO: Create LaunchDaemon for autorun
# TODO: Mail report
# TODO: Create flowchart/documentation
# TODO: Change backup script to touch .backup on success
# TODO: Fix status field if error
# TODO: Fix touch .backup (cut error?)
# TODO: Change period to 1 day
# TODO: Remove machine time
# TODO: Log when autorun (run with --auto)
# TODO: Put backup machine list inside script
# TODO: sla
# TODO: Change log location

# Exit if not root
user=`whoami`
if [ "$user" != "root" ]; then
	printf "Please run with admin privileges.\n"
	printf "Aborting...\n"
	exit 1
fi

# Set machine list file location
machine_list=/Users/hcadmin/Desktop/backup_machines.txt

# Create log file
today=`date +%Y_%m_%d`
now=`date "+%H:%M:%S"`
backup_report="/Users/hcadmin/Desktop/backup_report_${today}.log"
# backup_error="/Users/hcadmin/Desktop/backup_report_${today}.error"
touch "${backup_report}"

# Maximum age of .backup file in minutes (1 week)
max_age=10080
log_fmt='%m%t%Sm%t%N'

# Count number of machines
num_machines=`cat $machine_list | wc -l | xargs`
num_machines_ok=0

# Check if backup machine list exists
if [ ! -r $machine_list ]; then
	printf "Backup list ($machine_list) not found.\n"
	printf "Aborting...\n"
	exit 1
fi

# Check if backups are already mounted
if mount | grep "hc-storage.cougarnet.uh.edu/Backups on /Volumes/Backups" > /dev/null; then
	printf "Backup storage server already mounted. Unmount before proceeding.\n"
	printf "Aborting...\n"
	exit 1
fi

# Check if backup mount location already exists
if [ -d "/Volumes/Backups" ]; then
	printf "/Volumes/Backups already exists. Unmount the device on /Volumes/Backups before proceeding.\n"
	printf "Aborting...\n"
	exit 1
fi

# Note if running full verification
if [[ $* != *--full* ]]; then
	printf "Running full backup verification\n"
fi

# Mount backup storage server
printf "\nMounting network storage device...\n"
mkdir -p /Volumes/Backups

# Login and mount NAS disk
mount -v -t smbfs //hcverifybackup:'polebarkothertrain'@hc-storage.cougarnet.uh.edu/Backups /Volumes/Backups

# Navigate to backups directory
pushd /Volumes/Backups > /dev/null

# Log start time
printf "\n### BEGIN BACKUP REPORT ${today} ${now} ###\n" >> ${backup_report}

# Print table headers
printf "Machine\tUnix time\tReadable time\tLast modified directory\tStatus\n\n" >> ${backup_report}

# Set up exit trap (in case of failure or manual exit)
function cleanup()
{
	# Log end time
	now=`date "+%H:%M:%S"`
	printf "\n$num_machines_ok / $num_machines machines are OK" >> ${backup_report}
	printf "\n### END BACKUP REPORT ${now} ###\n" >> ${backup_report}

	# Unmount backup storage server when programs are done writing to it
	printf "\nUnmounting network storage device...\n"
	popd > /dev/null
	umount -vf /Volumes/Backups
	# rmdir /Volumes/Backups

	# Send report via email
	#mail -s "Backup Report $today" honorsit@central.uh.edu < $backup_report
}
trap cleanup EXIT

# Create function to perform `stat` on a stream of files
# function stat_all()
# {
# 	while IFS='' read -r d ; do
# 			stat -f "${log_fmt}" "$d"
# 	done
# }

# Log (append) to .backup file
function log_backup()
{
	local now=`date '+%H:%M:%S'`
	printf "$today ${now}: $1\n" >> '.backup'
}

# Read each line from machine list
counter=0
while IFS='' read -r machine || [[ -n "$machine" ]]; do
	counter=$((counter+1))
	printf "\nChecking backup for ${machine} ($counter/$num_machines)\n"

	# Check that the machine has a backup directory
	if [ -d "${machine}" ]; then
		# Navigate to machine directory
		pushd "${machine}" > /dev/null

		# Check if .backup file exists
		if [[ $* != *--full* ]]; then
				if [ -e '.backup' ]; then
					# Check last modified time of .backup file
					last_modified=`stat -f "${log_fmt}" '.backup'`
					printf "Found .backup file, last modified ${last_modified}\n"

					# Check if .backup file is recent (not older than 1 week)
					if ! test `find '.backup' -mmin +$max_age`
					then
						printf ".backup file is recent, skipping machine\n"
						printf "${machine}\t${last_modified}\tOK\n" >> ${backup_report}
						popd > /dev/null
						continue
					else
						printf ".backup file is too old, "
					fi
				else
					printf "Warning: .backup file does not exist, "
				fi
		fi

		# Recursive search for last modified time in directory tree
		printf "searching for latest modification...\n"
		last_modified=`find . -type d -print0 | xargs -0 -P 4 -n 10 sudo stat -f "${log_fmt}" | max`
		# last_modified=`find . -type d -print0 | xargs -0 -P 2 -n 10 sudo stat -f "${log_fmt}" | sort -nr | head -1`
		# last_modified=`find . -type d | stat_all | sort -nr | head -1`
		# last_modified=`find . -type d -exec sudo stat -f "%m%t%Sm%t%N" {} + | sort -nr | head -1`
		# last_modified=`find . -type d -print -ls | sort -nr | head -1 | awk '{print $1,"\t",$8,$9,$10,"\t",$11}'`

		# If recursive search failed, log error and continue to next machine
		if [ $? -gt 0 ]; then
			printf "Error: failed to find latest modified directory\n"
			printf "Skipping to next machine\n"
			printf "${machine}\t\t\tERROR: RECURSIVE SEARCH FAILED" >> ${backup_report}
			# DON'T TOUCH .backup FILE HERE
			# log_backup "Error: failed to find latest modified directory"
			popd > /dev/null
			continue
		fi

		# Create/update .backup file (modified time equal to last modified directory)
		mod_dir=`echo "$last_modified" | cut -f 3`
		# TODO: somehow not escaping mod_dir spaces properly
		touch -m -r "${mod_dir}" '.backup'

		# Put last modified information in .backup file
		log_backup "Last modified directory: ${last_modified}"

		# Display results
		printf "${last_modified}\n"

		# Add to report
		printf "${machine}\t${last_modified}\tOK\n" >> ${backup_report}

		# Increment OK counter
		$num_machines_ok=$((num_machines_ok + 1))

		# Return to backups directory
		popd > /dev/null
	else
		printf "Warning: ${machine} is not found on hc-storage\n"
		printf "${machine}\t\t\tERROR: MACHINE NOT FOUND\n" >> ${backup_report}
	fi
done <$machine_list
