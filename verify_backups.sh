
#!/bin/bash

###########################################################
# Automatic Backup Verification Script
# for The Honors College IT - The University of Houston
# @author  Max Ciotti and Chris Holley
# @date    7 September 2016
# @license MIT
###########################################################

# http://stackoverflow.com/questions/5566310/
# http://stackoverflow.com/questions/10929453/

# TODO: Create LaunchDaemon for autorun
# TODO: Create flowchart/documentation
# TODO: Fix status field if error
# TODO: Fix touch .backup (cut error?)

#Determine Run Environment
host=`scutil --get LocalHostName`
if [ "${host}" == "hc-deployment" ]; then
	run_mode="prod"
else
	run_mode="dev"
fi

# Create log file
today=`date +%Y_%m_%d`
now=`date "+%H:%M:%S"`
if [ "${run_mode}" == "prod" ]; then
	backup_report="/usr/local/honors/backup_report_${today}.log"
	backup_log="/usr/local/honors/backup_log_${today}.log"
else
	#Dev paths, change if needed
	backup_report="/Users/cholley/Desktop/backup_report_${today}.log"
	backup_log="/Users/cholley/Desktop/backup_log_${today}.log"
fi
touch "${backup_report}"
touch "${backup_log}"

# Exit if not root	
user=`whoami`
if [ "$user" != "root" ]; then
	printf "ERROR: Please run with admin privileges.\n" >> ${backup_log}
	printf "Aborting...\n" >> ${backup_log}
	exit 1
fi

# Set machine list file location
if [ "${host}" == "prod" ]; then
	machine_list="/usr/local/honors/backup_verification/backup_machines.txt";
else
	#Dev path change if needed
	machine_list="/Users/cholley/Documents/backup_verification/backup_machines.txt";
fi

# Check if backup machine list exists
if [ ! -r $machine_list ]; then
	printf "ERROR: Backup list ($machine_list) not found.\n" >> ${backup_log}
	printf "Aborting...\n" >> ${backup_log}
	exit 1 
fi

# Count number of machines
num_machines=`cat $machine_list | wc -l | xargs`
num_machines_ok=0

# Check if backups are already mounted
if mount | grep "hc-storage.cougarnet.uh.edu/Backups on /Volumes/Backups" > /dev/null; then
	printf "ERROR: Backup storage server already mounted. Unmount before proceeding.\n" >> ${backup_log}
	printf "Aborting...\n" >> ${backup_log}
	exit 1
fi

# Check if backup mount location already exists
if [ -d "/Volumes/Backups" ]; then
	printf "ERROR: /Volumes/Backups already exists. Unmount the device on /Volumes/Backups before proceeding.\n" >> ${backup_log}
	printf "Aborting...\n" >> ${backup_log}
	exit 1
fi

# Mount backup storage server
printf "\nMounting network storage device...\n" >> ${backup_log}
mkdir -p /Volumes/Backups

# Login and mount NAS disk
mount -v -t smbfs //hcverifybackup:'polebarkothertrain'@hc-storage.cougarnet.uh.edu/Backups /Volumes/Backups

# Maximum age of .backup file in minutes (3 days)
max_age=4320
log_fmt='%m%t%Sm%t%N'

# Note if running full verification
if [[ $* != *--full* ]]; then
	printf "Running full backup verification\n" >> ${backup_report}
else
	printf "Running compressed backup verification\n" >> ${backup_report}
fi

# Navigate to backups directory
pushd /Volumes/Backups > /dev/null

# Log start time
printf "\n### BEGIN BACKUP REPORT ${today} ${now} ###\n" >> ${backup_report}

# Print table headers
printf "Machine\t\tUnix time\t\tReadable time\t\tLast modified dir\tStatus\n\n" >> ${backup_report}

# Set up exit trap (in case of failure or manual exit)
function cleanup()
{

	# Log end time
	now=`date "+%H:%M:%S"`
	printf "\n$num_machines_ok / $num_machines machines are OK" >> ${backup_report}
	printf "\n### END BACKUP REPORT ${now} ###\n" >> ${backup_report}
	
	#Send report via email
	cat ${backup_report} | mail -s "Backup Report ${today}" cmholley97@gmail.com

	# Unmount backup storage server when programs are done writing to it
	printf "\nUnmounting network storage device...\n" >> ${backup_log}
	popd > /dev/null
	umount -vf /Volumes/Backups
	# rmdir /Volumes/Backups

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
i=0
while IFS='' read -r machine || [[ -n "$machine" ]]; do
	i=$((i+1))
	printf "\nChecking backup for ${machine} ($i/$num_machines)\n" >> ${backup_log}

	# Check that the machine has a backup directory
	if [ -d "${machine}" ]; then
		# Navigate to machine directory
		pushd "${machine}" > /dev/null

		# Check if .backup file exists
		if [[ $* != *--full* ]]; then
				if [ -e '.backup' ]; then
					# Check last modified time of .backup file
					last_modified=`stat -f "${log_fmt}" '.backup'`
					printf "Found .backup file, last modified ${last_modified}\n" >> ${backup_log}

					# Check if .backup file is recent (not older than 3 days)
					if ! test `find '.backup' -mmin +$max_age`
					then
						printf ".backup file is recent, skipping machine\n" >> ${backup_log}
						printf "${machine}\t\t${last_modified}\t\tOK\n" >> ${backup_report}
						popd > /dev/null
						continue
					else
						printf ".backup file is too old, " >> ${backup_log}
					fi
				else
					printf "Warning: .backup file does not exist, " >> ${backup_log}
				fi
		fi

		# Recursive search for last modified time in directory tree
		printf "searching for latest modification...\n" >> ${backup_log}
		# last_modified =`find . -type d -print0 | xargs -0 -P 4 -n 10 sudo stat -f "${log_fmt}" | sort -rn | max`
		last_modified=`find . -type d -print0 | xargs -0 -P 2 -n 10 sudo stat -f "${log_fmt}" | sort -nr | head -1`
		# last_modified=`find . -type d | stat_all | sort -nr | head -1`
		# last_modified=`find . -type d -exec sudo stat -f "%m%t%Sm%t%N" {} + | sort -nr | head -1`
		# last_modified=`find . -type d -print -ls | sort -nr | head -1 | awk '{print $1,"\t",$8,$9,$10,"\t",$11}'`

		printf "Last modified found\n" >> ${backup_log}
		# If recursive search failed, log error and continue to next machine
		if [ $? -gt 0 ]; then
			printf "Error: failed to find latest modified directory\n" >> ${backup_log}
			printf "Skipping to next machine\n" >> ${backup_log}
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
		printf "${last_modified}\n" >> ${backup_log}

		# Add to report
		printf "${machine}\t${last_modified}\tOK\n" >> ${backup_report}

		# Increment OK counter
		num_machines_ok=$((num_machines_ok + 1))

		# Return to backups directory
		popd > /dev/null
	else
		printf "Warning: ${machine} is not found on hc-storage\n" >> ${backup_log}
		printf "${machine}\t\t\tERROR: MACHINE NOT FOUND\n" >> ${backup_report}
	fi
done <$machine_list
