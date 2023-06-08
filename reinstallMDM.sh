#!/bin/bash

###############################################
# This script is intended to remove an MDM    #
# profile and prompt the user to install      #
# a new MDM profile locally.                  #
# If the user is not a local admin, they will #
# be temporarily promoted.                    #
# Contains elements of this script:           #
# https://github.com/jamf/MakeMeAnAdmin       #
###############################################

###############################################
# Check variables and set to default if empty.#
###############################################

if [ -z "${4}" ]; then
	echo "Parameter 4 not set, defaulting to /private/var/tmp/enrollmentProfile.mobileconfig"
	4="/private/var/tmp/enrollmentProfile.mobileconfig"
else
	echo "Enrollment Profile path set to $4"
fi

if [ -z "${3}" ]; then
  echo "User parameter was empty."
  userName=$(/bin/ls -la /dev/console | cut -d " " -f 4)
  if [ -z "$userName" ]; then
    echo "No user logged on."
		exit 1
  fi
else
  userName="${3}" # Why the brackets you ask? To properly use parameters 10 and 11
fi

promoteAdmin () {
#########################################################
# write a daemon that will let you remove the privilege #
# with another script and chmod/chown to make 			#
# sure it'll run, then load the daemon					#
#########################################################

#Create the plist
sudo defaults write /Library/LaunchDaemons/removeAdmin.plist Label -string "removeAdmin"

#Add program argument to have it run the update script
sudo defaults write /Library/LaunchDaemons/removeAdmin.plist ProgramArguments -array -string /bin/sh -string "/Library/Application Support/JAMF/removeAdminRights.sh"

#Set the run inverval to run every 5 minutes
sudo defaults write /Library/LaunchDaemons/removeAdmin.plist StartInterval -integer 300

#Set run at load
sudo defaults write /Library/LaunchDaemons/removeAdmin.plist RunAtLoad -boolean yes

#Set ownership
sudo chown root:wheel /Library/LaunchDaemons/removeAdmin.plist
sudo chmod 644 /Library/LaunchDaemons/removeAdmin.plist

#Load the daemon
launchctl load /Library/LaunchDaemons/removeAdmin.plist
sleep 10

#########################
# make file for removal #
#########################

if [ ! -d /private/var/userToRemove ]; then
	mkdir /private/var/userToRemove
	echo $userName >> /private/var/userToRemove/user
	else
		echo $userName >> /private/var/userToRemove/user
fi

##################################
# give the user admin privileges #
##################################

/usr/sbin/dseditgroup -o edit -a $userName -t user admin

########################################
# write a script for the launch daemon #
# to run to demote the user back and   #
# then pull logs of what the user did. #
########################################

cat << 'EOF' > /Library/Application\ Support/JAMF/removeAdminRights.sh
if [[ -f /private/var/userToRemove/user ]]; then
	userToRemove=$(cat /private/var/userToRemove/user)
	echo "Removing $userToRemove's admin privileges"
	/usr/sbin/dseditgroup -o edit -d $userToRemove -t user admin
	rm -f /private/var/userToRemove/user
	launchctl unload /Library/LaunchDaemons/removeAdmin.plist
	rm /Library/LaunchDaemons/removeAdmin.plist
	log collect --last 5m --output /private/var/userToRemove/$userToRemove.logarchive
fi
EOF
}

########################################
# Check for new MDM profile.           #
# If found, remove existing.           #
########################################

if [[ -f $4 ]]; then
	echo "New MDM profile found, proceeding to removal and reinstall."
  jamf removeMDMProfile
else
  echo "MDM profile not found, check packaging and deployment path. Exiting."
	exit 1
fi

########################################
# Check for admin - if user does not   #
# have admin rights, promote for 15m.  #
########################################

if [[ `/usr/bin/dscl . read /Groups/admin GroupMembership | /usr/bin/grep -c $userName` == 1 ]]; then
	echo "$userName is a local administrator, continuing to profile install."
else
  echo "$userName is not an admin, promoting user."
	promoteAdmin
fi

########################################
# Prompt for install of MDM profile.   #
########################################

open /System/Library/PreferencePanes/Profiles.prefpane $4

exit 0
