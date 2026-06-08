#!/bin/bash
# shellcheck disable=SC2024
#
# getofn.sh
#

# Oracle (database) Free Now! (OFN) 
# script to download the OFN tools and start install process

# Internal settings
SCRIPTVER=1.0
SCRIPTNAME=$(basename "${BASH_SOURCE[0]}")
SCRIPTDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# variables for script
wait_sec=60                                        # number of seconds to wait after cloud-init before reboot
repo_url=https://github.com/ggordham/ofn           # github URL for OFN
package_root=ggordham-ofn                          # github packate name
target_path=/opt/ofn                               # target install path
install_script=ofn_inst.sh                         # install script
log_file=/tmp/getofn-$( date +%Y%m%d-%H%M%S ).log  # log file for this script
cur_user=$( /usr/bin/id -un )                      # user running script
cur_group=$( /usr/bin/id -gn )                     # primary group of user running script
file_owner=oracle:oinstall                         # target file ownership
refresh=FALSE                                      # default do not refresh
reboot=FALSE                                       # default do not reboot

# retun command line help information
function help_getofn {
  echo >&2
  echo "$SCRIPTNAME                                    " >&2
  echo "   Download ofn scripts and initiate install   " >&2
  echo "   version: $SCRIPTVER                         " >&2
  echo >&2
  echo "Usage: $SCRIPTNAME [-h --debug --test ]         " >&2
  echo "-h          give this help screen               " >&2
  echo "--refresh   download scripts only               " >&2
  echo "--reboot    initiate reboot after cloud-init    " >&2
  echo "--debug     turn on debug mode                  " >&2
  echo "--test      turn on test mode                   " >&2
  echo "--version | -v Show the script version          " >&2
}

# simple trim white space function
function trim() {
    local var="$*"
    # remove leading whitespace characters
    var="${var#"${var%%[![:space:]]*}"}"
    # remove trailing whitespace characters
    var="${var%"${var##*[![:space:]]}"}"
    printf '%s' "$var"
}

# Process command line options
# shellcheck disable=SC2068
my_opts=$(getopt -o hv --long debug,test,version,refresh,reboot -n "$SCRIPTNAME" -- $@)
if (( $? > 0 )); then
   (( badopt=1 ))
else
    eval set -- "$my_opts"
    while true; do
        case $1 in
            "-h") help_getofn                          #  help
                  exit 1;;
             "--refresh") refresh=TRUE                    # refresh mode
                      shift ;;
             "--reboot") reboot=TRUE                      # reboot after cloud-init mode
                      shift ;;
            "--debug") DEBUG=TRUE                         # debug mode
                       set -x
                       shift ;;
             "--test") TEST=TRUE                           # test mode
                      shift ;;
            "--version"|"-v") echo "$SCRIPTNAME version: $SCRIPTVER" >&2
                      exit 0;;
            "--") shift; break;;                             # finish parsing
                  *) echo "ERROR! Bad command line option passed: $1"
                     (( badopt=1 ))
                     break ;;                                    # unknown flag
        esac
    done
fi

if (( badopt > 0 )); then 
    echo "ERROR bad command line option!"
    exit 1
fi


############################################################################################
# start here

echo "===== getofn.sh Starting" | /usr/bin/tee -a "${log_file}"
echo "  running as user: $cur_user " | /usr/bin/tee -a "${log_file}" 
echo "  running as group: $cur_group " | /usr/bin/tee -a "${log_file}"

if [ "$DEBUG" == "TRUE" ]; then echo "DEBUG Mode Enabled!" | /usr/bin/tee -a "${log_file}"; fi
if [ "$TEST" == "TRUE" ]; then echo "TEST Mode Enabled, commands will not be run." | /usr/bin/tee -a "${log_file}"; fi
if [ "$refresh" == "TRUE" ]; then echo "refresh Mode Enabled, will only download scripts." | /usr/bin/tee -a "${log_file}"; fi
if [ "$reboot" == "TRUE" ]; then echo "reboot after cloud-init Mode Enabled." | /usr/bin/tee -a "${log_file}"; fi

# tar has to be installed first
if ! /bin/rpm --quiet -q tar; then
    echo "tar not installed, installing." >> "${log_file}"
    /bin/dnf install -y tar | /usr/bin/tee -a "${log_file}" 2>&1
fi

# make the target directory for ofn
echo "  Making target path: $target_path" | /usr/bin/tee -a "${log_file}"
[[ ! -d "${target_path}" ]] && sudo /usr/bin/mkdir "${target_path}" >> "${log_file}" 2>&1
/usr/bin/sudo /usr/bin/chown "${cur_user}" "${target_path}" >> "${log_file}" 2>&1
/usr/bin/sudo /usr/bin/chgrp "${cur_group}" "${target_path}" >> "${log_file}" 2>&1

# download the ofn scripts
echo "  Downloading ofn scripts from: ${repo_url}/scripts/tstOraInst.sh" | /usr/bin/tee -a "${log_file}"
if [ "$TEST" == "TRUE" ]; then
    echo "Test mode, not running: /usr/bin/curl -L ${repo_url}/tarball/main | tar xz -C ${target_path} --strip=1 ${package_root}-???????" | /usr/bin/tee -a "${log_file}"
else
    /usr/bin/curl -L ${repo_url}/tarball/main | tar xz -C "${target_path}" --strip=1 "${package_root}-???????"  | /usr/bin/tee -a "${log_file}"

    # if we are in refresh mode, assume oracle user exists
    if [ "${refresh}" == "TRUE" ]; then
        echo "  Refresh mode, setting ofn ownersip to: ${file_owner}" | /usr/bin/tee -a "${log_file}"
        /usr/bin/chown -R "${file_owner}" "${target_path}"
    fi

    # set scripts to executable
    /usr/bin/find "${target_path}" -name \*.sh -exec /usr/bin/chmod 754 {} \; >> "${log_file}" 2>&1

fi

# if we are reboot mode setup the reboot process
if [ "${reboot}" == "TRUE" ]; then
    echo "Setting up automated reboot and install." | /usr/bin/tee -a "${log_file}"
    # check if cloud-init is finished then reboot
    while [ ! "$( trim "$( /usr/bin/sudo /usr/bin/cloud-init status | /usr/bin/cut -d: -f2 )" )" == "done" ]; do
        echo "  Waiting for Cloud init to complete, sleeping 30 seconds" | /usr/bin/tee -a "${log_file}"
        sleep 30
    done
    
    # install the ofn install script for after reboot
    echo "Installing reboot script: ${target_path}/${install_script}" | /usr/bin/tee -a "${log_file}"
    if [ "$TEST" == "TRUE" ]; then
        echo "Test mode, not running: ${SCRIPTDIR}/runonce.sh ${target_path}/${install_script}" | /usr/bin/tee -a "${log_file}"
    else
        "${SCRIPTDIR}/runonce.sh" "/usr/bin/sudo -u root ${target_path}/${install_script} > /tmp/cron-ofn_inst.log 2>&1" | /usr/bin/tee -a "${log_file}"
    fi
    
    # reboot after cloud-init is finished
    #  Be sure to exit 0 for terraform to get good status
    echo "initiating reboot $( date )" | /usr/bin/tee -a "${log_file}"
    if [ "$TEST" == "TRUE" ]; then
        echo "Test mode, not running: /usr/bin/nohup /bin/bash -c /usr/bin/sleep ${wait_sec} && /usr/bin/sudo /usr/sbin/reboot" | /usr/bin/tee -a "${log_file}"
    else
        /usr/bin/nohup /bin/bash -c "/usr/bin/sleep ${wait_sec} && /usr/bin/sudo -u root /usr/sbin/reboot" >> /tmp/ofn-reboot.log 2>&1 &
        jobs | /usr/bin/tee -a "${log_file}"
    fi
fi

echo "Exiting  $( date )" | /usr/bin/tee -a "${log_file}"
echo "===== getofn.sh Finished" | /usr/bin/tee -a "${log_file}"
exit 0

# END 
