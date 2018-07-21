#!/bin/bash -i

# This bash script is designed to automate the downloading of Dash Cam video, along with
# the associated GPS and thumbfile files, to a linux based system.

# It has been tested with the BlackVue DR650GW and the DR650S

# To run the script on boot from the pi home directory, add the following line to /etc/rc.local above the exit 0 statement:    (sudo nano /etc/rc.local)
# su pi -c '/home/pi/dashcam.sh >> /tmp/dashcam.log 2>&1' &

# Author: pi-resource.com
# Version: 1.2
# Date: 2017-09-04

############
# Settings #
############
#
#
# Dashcam - IP address. If specifying a URL ensure you include the "http://" portion
dashcam_ip=192.168.1.140
# Dashcam - path and filename of the webpage that lists the files available for download. For the DR650GW-2CH it is 'blackvue_vod.cgi'
dashcam_webpage=blackvue_vod.cgi
# Dashcam - Possible file name extensions that are to be downloaded, listed in an array with a space as the delimiter
dashcam_file_extensions_array=(.gps .3gf F.thm R.thm R.mp4 F.mp4)
# Location to save downloaded files (no / on the end)
download_dest=/mnt/hdd1/dashcam
#
# Delete files older than the specified number of days
# 0 = Off
delete_old_files=0
#
# This script will delete the oldest files once the disk space utilisation reaches a specified percentage.
# Default is set to 95%, once more than 95% of the disk has been used the oldest files will be deleted.
# To disable, set to a value greater than onehundred. i.e. 101
filesystem=/dev/root
filesystemUsedSpaceLimit=95
#
# If the dashcam is not in range, or the downloads have completed, how many minutes to wait before checking again.
timer=1

#############
# Constants #
#############
DEFAULT=$'\e[0m'
BOLD=$'\e[1m'
UNDERLINE=$'\e[4m'
RED=$'\e[0;91m'
GREEN=$'\e[0;92m'
YELLOW=$'\e[0;93m'
BLUE=$'\e[0;94m'
MAGENTA=$'\e[0;95m'
CYAN=$'\e[0;96m'

#############
# FUNCTIONS #
#############

# execution_time ( **************************** NO LONGER USED IN THIS SCRIPT ****************************************** )
#
# input: start epoch, end epoch
# function: converts a number of seconds into a human readable string 
# returns: prints the number of days, hours, minutes and seconds. 
function execution_time {
    num=$2-$1
    min=0
    hour=0
    day=0
    if((num>59));then
	    ((sec=num%60))
        ((num=num/60))
        if((num>59));then
    		((min=num%60))
            ((num=num/60))
            if((num>23));then
		    	((hour=num%24))
                ((day=num/24))
            else
                ((hour=num))
			fi
        else
            ((min=num))
		fi
    else
        ((sec=num))
	fi
	
	if [ $day -gt 0 ]; then
	printf "%s\nScript took %i day(s), %i hour(s), %i min(s), %i sec(s) to complete" $DEFAULT $day $hour $min $sec
    elif [ $hour -gt 0 ]; then
	printf "%s\nScript took %i hour(s), %i min(s), %i sec(s) to complete" $DEFAULT $hour $min $sec
	elif [ $min -gt 0 ]; then
	printf "%s\nScript took %i min(s), %i sec(s) to complete" $DEFAULT $min $sec	
	else
	printf "%s\nScript took %i sec(s) to complete" $DEFAULT $sec
    fi
}

# Wait function
# arg1 = time to wait in seconds
# arg2 = text to place before countdown
# arg3 = text to place after countdown
function countDown {
	if [ "$1" -lt  1 ]; then
		return
    else
	
		# If tput command is supported by the OS, then hide cursor as it makes the count down look nicer. Must reinstate cursor once count down has finished.
		if which "tput" > /dev/null; then
			tput civis
		fi
		
		printf '\n'
		for (( seconds=$1; seconds>=0; seconds-- ))
		do
			if [ $seconds -gt 60 ]; then
				printf "\r%s %i Minute(s) %i Second(s) %s          " "$2" "$((seconds / 60))" "$((seconds % 60))" "$3"
			else
				printf "\r%s %i Second(s) %s         " "$2" "$seconds" "$3"			
			fi
			sleep 1
		done
	
		# restore terminal cursor, if tput command is supported
		if which "tput" > /dev/null; then
			tput cnorm
		fi	
    fi
}

# checkDashcamOnline
#
# input: dashcam IP address or URL
# function: pings the dashcam to determine if it is available
# output: 0 - dashcam online, 1 - dashcam offline.
function checkDashcamOnline {
	if wget -q --spider $dashcam_ip/$dashcam_webpage; then
		# Dashcam online
		return 1
	else
		# Dashcam NOT online
		return 0

	fi
}

# Check if script is already running
#
# inputs: none
# output: 0 - Yes, 0 - No
function checkIfScriptAlreadyRunning {
	if pidof -o %PPID -x "${0##*/}">/dev/null; then
        return 0
	else
		return 1
	fi
}

# Prints the intro out to screen.
function displayIntro {
	printf "%s%sDashcam download by pi-resource" $RED $UNDERLINE
	printf "\n%sThis bash script automates the downloading of Dash Cam video, along with the associated GPS and thumbfile files." $DEFAULT
	printf "\n%sFirst it checks if the dashcam is available, and if it is, it then queries the dashcam to determine if there are any new files available for download." $DEFAULT
	printf "\n%sNew files are then downloaded, the oldest first as these would be the first to be deleted from the Dash Cam." $DEFAULT
	printf "\n%sIf configured, any old files are removed from the local system." $DEFAULT
	printf "\n"	
	printf "\n%sAny Comments, questions or suggested improvements, please visit %s%shttp://www.pi-resource.com" $DEFAULT $BLUE $UNDERLINE
	printf "\n%sVersion: 1.1" $DEFAULT
	printf "\n%sRelease date: 2017-09-04" $DEFAULT
}

# Prints the configuration out to screen.
function displayConfig {
	printf "\n%s%sConfiguration" $MAGENTA $UNDERLINE
	printf "\n%s       -- Dash Cam IP/URL: %s%s%s%s" $DEFAULT $YELLOW $BOLD $UNDERLINE $dashcam_ip
	printf "\n%s       -- Dash Cam webpage which lists files: %s%s%s%s" $DEFAULT $YELLOW $BOLD $UNDERLINE $dashcam_webpage
	printf "\n%s       -- Location to save the downloaded files to: %s%s%s%s" $DEFAULT $YELLOW $BOLD $UNDERLINE $download_dest
	printf "\n%s       -- Old files to be deleted after set number of days?" $DEFAULT
	if [ $delete_old_files -eq 0 ]; then
		printf "%s%s%s%sNO" $DEFAULT $YELLOW $BOLD $UNDERLINE	
	else
		printf "%s %s%s%sYES%s - After %s%s%s%i day(s)" $DEFAULT $YELLOW $BOLD $UNDERLINE $DEFAULT $YELLOW $BOLD $UNDERLINE $delete_old_files
	fi	
	printf "\n%s       -- Oldest files will be deleted if the used disk space exceeds: %s%s%s%s%%%s"  $DEFAULT $YELLOW $BOLD $UNDERLINE "$filesystemUsedSpaceLimit" $DEFAULT	
}


# Displays a process bar
#	
# If the screen is less than 15 columns wide then only a percentage is displayed.
# For best results, hide the terminal cursor with tput civis before running the function.
# The terminal cursor can be restored with tput cnorm
# arg1 = counter
# arg2 = max value
function progress_bar {
	count=$1
	max=$2
	screen_width=$COLUMNS
	percentage=$((100*$count/$max))

	printf "\r%s%3i%%" $DEFAULT $percentage

	if [[ screen_width -ge 15 ]]; then
		# Screen is wide enough to display a progress bar.
	
		# Display spinner
		if [ $(( $count % 4 )) -eq 0 ]; then
			printf ' \'
		elif [ $(( $count % 4 )) -eq 1 ]; then
			printf ' |'
		elif [ $(( $count % 4 )) -eq 2 ]; then
			printf ' /'
		elif [ $(( $count % 4 )) -eq 3 ]; then
			printf ' -'
		fi

		# display progress bar
		progress_bar_width=$(($screen_width-10))
		progress_marks=$(($progress_bar_width*$count/$max))

		printf " ["

		for ((progress_bar_cursor_position=0; progress_bar_cursor_position<$progress_marks; progress_bar_cursor_position++)); do
			printf "="
		done
		
		printf ">"
		((++progress_bar_cursor_position))
		
		for ((progress_bar_cursor_position=$progress_bar_cursor_position; progress_bar_cursor_position<$progress_bar_width; progress_bar_cursor_position++)); do
			printf " "
		done

		printf "]"
	fi
}

###########################
# Start of main programme #
###########################

#########################################
# 1. Check if script is already running #
# If it is, then exit.                  #
#########################################
if checkIfScriptAlreadyRunning; then
	printf "%sProcess already running" $RED
	printf "%s\nExiting..." $DEFAULT
	printf "%s\n" $DEFAULT
	exit
else

	###########################################
	# 2. Display Introduction & Configuration #
	###########################################
	displayIntro
	printf "\n"
	displayConfig
	printf "\n"

	# Start infinite loop with no exit conditions.
	while :
	do	
	
		#################################
		# 2. Check if Dashcam is online #
		#################################
		printf "\n%sDash Cam online? " $DEFAULT
		if checkDashcamOnline; then
			printf "%s%s%sNo" $RED $BOLD $UNDERLINE
		else
			printf "%s%s%sYes" $YELLOW $BOLD $UNDERLINE

			######################################################################################################################
			# 3. Read file names from the dashcam.                                                                               #
			#                                                                                                                    #
			# Format producted by cgi script is:                                                                                 #
			#     n:/Record/20160118_112745_NR.mp4,s:1000000                                                                     #
			# filename format:                                                                                                   # 
			#     yyyymmdd_hhmmss_xy.ext                                                                                         #
			#         x = P, Parking mode                                                                                        #
			#         x = E, Emergency (i.e. gforce/impact trigger)                                                              #
			#         x = N, Normal driving mode                                                                                 #
			#         y = F, Front camera                                                                                        #
			#         y = R, Rear camera                                                                                         #
			# Note that only the mpg files are listed, not the thumbnail, gps or 3gf files.                                      #  
			# There will be additional files: .thm (for both Front and Rear); .gps; .3gf                                         #
			# Therefore, ignore the last character (R of F) on the .mpg file as this will be added back as part of the extension #
			######################################################################################################################

			printf "\n%sDownloading list of files from the Dash Cam:" $DEFAULT
			printf "\n\n"
			# produces a string with a space seperating each filename that is extracted.
			dashcam_file_name_string=$( curl $dashcam_ip/$dashcam_webpage | cut -d "," -f 1 -s | cut -c4-27 )

			# Dedupe - The array will contain duplicate file names if a rear camera is fitted, as an mpg file will exist with the
			# same file name except the last character ('F' [Front] or 'R' [Rear]) before the file extension.
			dashcam_file_name_string=$(echo "$dashcam_file_name_string" | tr ' ' '\n' | sort -u | tr '\n' ' ')

			# Convert the string into an array with space being the delimiter
			dashcam_file_name_array=($dashcam_file_name_string)

			# Loop through the file names, adding the extension and then check if the file has previously been downloaded.
			# If file has not been downloaded, add file name to a new array.
			files_on_dashcam=$((${#dashcam_file_name_array[@]} * ${#dashcam_file_extensions_array[@]}))
			counter=0
			counter_previously_downloaded=0
			dashcam_files_for_download=()

			# If tput command is supported by the OS, then hide cursor as it makes the 'progress bar' look nicer. Must reinstate cursor once progress bar has finished.
			if which "tput" > /dev/null; then
				tput civis
			fi
		
			printf "\n%sDash Cam has %i files, checking which ones require downloading:" $DEFAULT $files_on_dashcam
			printf "%s\n" $DEFAULT
			for ((i=0; i<${#dashcam_file_name_array[@]}; i++)) ; do
#			for ((i=0; i<50; i++)) ; do    # Used for debugging to fetch less files during the download
				for ((j=0; j<${#dashcam_file_extensions_array[@]}; j++)) ; do
					((++counter)) 
					progress_bar $counter $files_on_dashcam 
					if [ -e $download_dest/${dashcam_file_name_array[i]}${dashcam_file_extensions_array[j]} ] ; then
						# Already exists
						((++counter_previously_downloaded))
					else
						# Needs downloading
						dashcam_files_for_download=(${dashcam_files_for_download[@]} ${dashcam_file_name_array[i]}${dashcam_file_extensions_array[j]})
					fi		
				done
			done
		
			# restore terminal cursor, if tput command is supported
			if which "tput" > /dev/null; then
				tput cnorm
			fi		

			# Display summary
			printf "\n%s%i files do not need downloading" $DEFAULT $counter_previously_downloaded
			printf "\n%s%i files require downloading" $DEFAULT ${#dashcam_files_for_download[@]}

			########################################
			# 4. Download files from the Dash Cam. #
			########################################
			if [ ${#dashcam_files_for_download[@]} -gt 0 ]; then
				printf "\n\n"
				for ((i=0; i<${#dashcam_files_for_download[@]}; i++)) ; do
					printf "%sDownloading %i of %i:\n" $DEFAULT $((i+1)) ${#dashcam_files_for_download[@]}
					wget -x -nH -q --show-progress -P $download_dest $dashcam_ip/${dashcam_files_for_download[$i]}
				done
	
				# Display summary
				printf "%s\n%i files downloaded" $DEFAULT ${#dashcam_files_for_download[@]}
			fi
		fi

		##################################################
		# 5. Check disk space.                           #
		# If less than a set amount, delete oldest files #
		##################################################	
		diskSpaceUsed=$(df -H | grep $filesystem | awk '{ print $5 }' | cut -d'%' -f1)
		printf "\n%sChecking used disk space: " $MAGENTA

		if [ "$diskSpaceUsed" -gt $filesystemUsedSpaceLimit ]; then
			printf "%s%s%%" $RED "$diskSpaceUsed"
			printf "\n%sDeleting the following files to create disk space:" $MAGENTA

			while [ $(find $download_dest -type f | grep -v '/\.' | wc -l) -gt 0 ] && [ $(df -H | grep $filesystem | awk '{ print $5 }' | cut -d'%' -f1) -gt $filesystemUsedSpaceLimit ]
			do
				oldestFile=$(find $download_dest -type f | grep -v '/\.' | sort -r | tail -n 1)
				if rm "$oldestFile"; then
					printf "\n      %s%s%s DELETED" $DEFAULT "$oldestFile" $GREEN
				else
					printf "\n      %s%s%s ERROR - %s" $DEFAULT "$oldestFile" $RED $?
				fi
			done
		
			if [ $(df -H | grep $filesystem | awk '{ print $5 }' | cut -d'%' -f1) -gt $filesystemUsedSpaceLimit ]; then
				printf "\n%s      WARNING%s - There are no files identified for deleting that will create any more space" $CYAN $DEFAULT
			fi
		else
			printf "%s%s%%" $GREEN "$diskSpaceUsed"
		fi

		#########################################################
		# 6. Delete files older than a specified number of days #
		#########################################################	
		if [ $delete_old_files -gt 0 ]; then
			counter_deleted_files=0
			printf "\n%sChecking for files older than%s %i %sday(s):" $MAGENTA $DEFAULT $delete_old_files $MAGENTA
	
			for ((i=0; i<${#dashcam_file_extensions_array[@]}; i++)) ; do
				if [ $(find $download_dest -type f -mtime +$delete_old_files -name "*${dashcam_file_extensions_array[i]}" | wc -l) -gt 0  ] ; then
					file_to_be_deleted=$(find $download_dest -type f -mtime +$delete_old_files -name "*${dashcam_file_extensions_array[i]}")
					if rm "$file_to_be_deleted"; then
						printf "\n      %s%s -%s DELETED" $DEFAULT "$file_to_be_deleted" $GREEN
						((++counter_deleted_files))
					else
						printf "\n      %s%s -%s ERROR - %s" $DEFAULT "$file_to_be_deleted" $RED $?
						((++counter_deleted_files))
					fi
				fi
			done

			if [ $counter_deleted_files -eq 0 ]; then
				printf " %sNone" $GREEN
			fi
		fi
	
		#########################################
		# 7. Wait before restarting this script #
		#########################################
		countDown $((timer * 60)) $DEFAULT"Waiting" "minutes before restarting the cycle     "	

	done
fi
printf "\n$DEFAULT"
exit

