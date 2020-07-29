#!/bin/bash
#################################################
# Script written by Eric Johnson - 06/16/2020   #
# This script contains components written by    #
# Fabian Ulmrich, 07/02/2015                    #
#################################################

# prints colored text
print_style () {

    if [ "$2" == "info" ] ; then
        COLOR="96m";
    elif [ "$2" == "success" ] ; then
        COLOR="92m";
    elif [ "$2" == "warning" ] ; then
        COLOR="93m";
    elif [ "$2" == "danger" ] ; then
        COLOR="91m";
    else #default color
        COLOR="0m";
    fi

    STARTCOLOR="\e[$COLOR";
    ENDCOLOR="\e[0m";

    printf "$STARTCOLOR%b$ENDCOLOR" "$1";
}

# clear the console prior to user input
clear
print_style "This script converts a Smart Computer or Mobile Device Group to a Static Group.\n" "info"

# authentication loop
while true; do

  print_style "Input Jamf Pro URL: (ex: https://example.jamfcloud.com)\n"
  read jpURL
  print_style "Input Jamf Pro username:\n"
  read jpUser
  print_style "Input Jamf Pro password:\n"
  read -s jpPassword

  jpStatus=$( curl -s -u ${jpUser}:${jpPassword} -o /dev/null -w '%{http_code}' -X GET ${jpURL}/JSSResource/computergroups )

  # HTTP Status check. Only exits the loop on a successful (200) authentication.
  if [ $jpStatus -eq 200 ]; then
    print_style "Successfully authenticated.\n" "success"
    break
  elif [ $jpStatus -eq 401 ]; then
    print_style "AUTHENTICATION FAILED. Please re-enter your information.\n\n" "danger"
  elif [ $jpStatus -eq 404 ]; then
    print_style "404 error - not found.\n\n" "danger"
  else
    print_style "Command failed. HTTP Status was $jpStatus. Please re-enter your information.\n\n" "danger"
  fi

done

# Smart to Static Conversion loop
while true; do

    # Determine if Computer or Mobile Device Group
    clear
    print_style "Enter \"1\" for Computer Groups or \"2\" for Mobile Device Groups:\n"
    read groupType

    # Start Computer Group conversion
    if [ $groupType = "1" ]; then

      print_style "Computer Group selected.\n" "info"
      print_style "ID of Smart Group:\n"
      read smartID #ID of the smart group
      print_style "Name of New Static Group:\n"
      read staticName #Name of the new static group that you want created in the JSS, do not create the group, the script does that

      #Get a list of computers currently in the smart group
      var=`curl -s -u ${jpUser}:${jpPassword} ${jpURL}/JSSResource/computergroups/id/${smartID} -X GET | awk -F 'computers' '{print $2}'`

      #Reformatting to create the XML
      a="<?xml version=\"1.0\" encoding=\"UTF-8\"?>"
      b="<computer_group><name>${staticName}</name>"
      c="<is_smart>false</is_smart><computers"
      d="computers></computer_group>"
      var=${a}${b}${c}${var}${d}

      #Submit the XML to the API
      updateResponse=$( curl -s -u ${jpUser}:${jpPassword} ${jpURL}/JSSResource/computergroups/name/${staticName} -d "$var" -H "Content-Type: text/xml" -X POST -w '%{http_code}')
      updateStatus=${updateResponse: -3}

      #Check if group creation was successful.
      if [ $updateStatus -eq 201 ]; then

        # Pull ID from XML
        staticXML=${updateResponse%???}
        staticID=$( echo "$staticXML" | xmllint --xpath "string(//id)" - )
        # Build URLs for old and new groups.
        smartURL="${jpURL}/smartComputerGroups.html?id=${smartID}"
        staticURL="${jpURL}/staticComputerGroups.html?id=${staticID}"
        print_style "Group Created.\nOld Smart Group: ${smartURL}\nNew Static Group: ${staticURL}\n" "info" # These links can be opened by right-clicking the output.

        # If the update was not successful, list all known errors.
        elif [ $updateStatus -eq 409 ]; then
          print_style "Conflict - Group Name may already exist.\n" "danger"
        elif [ $updateStatus -eq 404 ]; then
          print_style "Group not found.\n" "danger"
        else
          print_style "Unknown error: $updateStatus"
      fi

    # Start Mobile Device conversion
    elif [ $groupType = "2" ]; then
      print_style "\nMobile Device Group selected.\n" "info"
      print_style "Input ID of Smart Group:\n"
      read smartID #ID of the smart group
      print_style "Input name of New Static Group:\n"
      read staticName #Name of the new static group that you want created in the JSS, do not create the group, the script does that

      #Get a list of mobile devices currently in the smart group
      var=`curl -s -u ${jpUser}:${jpPassword} ${jpURL}/JSSResource/mobiledevicegroups/id/${smartID} -X GET | awk -F 'mobile_devices' '{print $2}'`
      #Reformatting to create the XML
      a="<?xml version=\"1.0\" encoding=\"UTF-8\"?>"
      b="<mobile_device_group><name>${staticName}</name>"
      c="<is_smart>false</is_smart><mobile_devices"
      d="mobile_devices></mobile_device_group>"
      var=${a}${b}${c}${var}${d}

      #Submit the XML to the API
      updateResponse=$( curl -s -u ${jpUser}:${jpPassword} ${jpURL}/JSSResource/mobiledevicegroups/name/${staticName} -d "$var" -H "Content-Type: text/xml" -X POST -w '%{http_code}' )
      updateStatus=${updateResponse: -3}

      #Check if group creation was successful.
      if [ $updateStatus -eq 201 ]; then

        # Pull ID from XML
        staticXML=${updateResponse%???}
        staticID=$( echo "$staticXML" | xmllint --xpath "string(//id)" - )
        # Build URLs for old and new groups.
        smartURL="${jpURL}/smartMobileDeviceGroups.html?id=${smartID}"
        staticURL="${jpURL}/staticMobileDeviceGroups.html?id=${staticID}"
        print_style "Group Created.\nOld Smart Group: ${smartURL}\nNew Static Group: ${staticURL}\n" "info"

        # If the update was not successful, list all known errors.
        elif [ $updateStatus -eq 409 ]; then
          print_style "Conflict - Group Name may already exist.\n" "danger"
        elif [ $updateStatus -eq 404 ]; then
          print_style "Group not found.\n" "danger"
        else
          print_style "Unknown error: $updateStatus\n"
      fi
    fi

    # Determine whether to continue the conversion loop.
    print_style "Convert another Smart Group? y/n\n"
    read continueInput
    if [ $continueInput != "y" ]; then # exits the loop/script on any input other than "y"
      print_style "Exiting.\n" "info"
      exit 0
    fi
done
