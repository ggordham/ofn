#!/bin/bash
# ofn_inst.sh

# current Oracle AI Database free name / version
DBFPNAME=oracle-ai-database-preinstall-26ai
DBFPVER=1.0-1
DBFNAME=oracle-ai-database-free-26ai
DBFVER=23.26.2-1
# previous version
#DBFNAME=oracle-database-free-23ai
# DBFVER=23.9-1, 23.26.0-1

# Internal settings
SCRIPTVER=1.0.0
SCRIPTNAME=$(basename "${BASH_SOURCE[0]}")
export OFNINST=TRUE                    # disable pre-checks before loading
source "$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"/ofn.shlib
# source "$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"/ofn_ora.shlib

# Setup run directory as system config
mkOFNRUNDir(){

    local my_var_dir=${1}
    local my_log=${2}
    local my_tmpfile=/etc/tmpfiles.d/ofn.conf

    if [ -f "${my_tmpfile}" ]; then
    # Make tempfile.d configuration file
        logMesg 0 "Temp config exists: ${my_tmpfile}" I "${my_log}"
    else
        touch "${my_tmpfile}"
        echo "# Oracle Free Now (OFN) install $(/bin/date )" > "${my_tmpfile}"
        echo "# Type Path Mode UID GID Age Argument"        >> "${my_tmpfile}"
        echo "d ${my_var_dir} 0755 oracle oinstall - -"     >> "${my_tmpfile}"
        logMesg 0 "Created tempfiles config: ${my_tmpfile}" I "${my_log}"
 
        # create directory
        /bin/systemd-tmpfiles --create "${my_tmpfile}"
        if (( $? > 0 )); then
            logMesg 1 "Could not create rundir: ${my_var_dir}" E "${my_log}"
        else
            logMesg 0 "Created rundir: ${my_var_dir}" I "${my_log}"
        fi
    fi
}

# function to make directories needed by OFN
mkOFNDir(){

    local my_dir=$1
    local my_log=$2
    local my_return=0

    /bin/mkdir -p "${my_dir}" >> "${my_log}" 2>&1
    if [ -d "${my_dir}" ]; then
        logMesg 0 "Created directory: ${my_dir}" I "${my_log}"
        my_return=0
    else
        logMesg 2 "Could not created directory: ${my_dir}" E "${my_log}"
        my_return=2
    fi

    return ${my_return}
}

# function to downlaod and install required RPM files
instOFNRPM(){

    local my_url=$1
    local my_log=$2
    local my_return=0
    local my_rpm

    my_rpm=$( /bin/basename "${my_url}" )

    # check if RPM is installed
    if /bin/rpm -q --quiet "${my_rpm%.*}"; then
        logMesg 0 "RPM ${my_rpm} already installed." I "${my_log}"
    else
        # downlaod and try to install the rpm
        logMesg 0 "Downlaoding and installing rpm ${my_rpm}" I "${my_log}"
        cd "${ofndata}/stage" >> "${my_log}" 2>&1
        /bin/curl -O -L "${my_url}" >> "${my_log}" 2>&1
        if (( $? > 0 )); then
            logMesg 2 "Could not download rpm ${my_rpm}" E "${my_log}"
            my_return=2
        else
            /bin/dnf -y install "${my_rpm}" >> "${my_log}" 2>&1
            if (( $? > 0 )); then
                logMesg 2 "Could not install rpm ${my_rpm}" E "${my_log}"
            fi
            cd - >> "${my_log}" 2>&1
        fi
    fi

    return ${my_return}
}

############################################################################################
# start here

# verify that we are root to run this script
if [ "x$USER" != "xroot" ];then logMesg 1 "You must be logged in as root to run this script" E "NONE"; exit 1; fi

# setup log file
log_file="${ofnlog}/db-install-$( /bin/date +%Y%m%d-%H%M%S ).log"
log_temp=/tmp/ofn-inst.log
return_code=0

logMesg 0 "Starting ${SCRIPTNAME} ${SCRIPTVER}" I "${log_temp}"

# setup log dir and deal with inital log file
if [ ! -d "${ofnlog}" ]; then
    mkOFNDir "${ofnlog}" "${log_temp}" || return_code=2 
    if (( return_code == 0 )); then
        /bin/mv "${log_temp}" "${log_file}"
    else
        logMesg 2 "Could not create log directory: ${ofnlog}" E "${log_temp}"
        logMesg 2 "Check log file at: ${log_temp}" E "NONE"
        exit 2
    fi
fi

# diplay log file location
logMesg 0 "Log file for install at: ${log_file}" I "NONE"

# make required directories
if [ ! -d "/opt/oracle" ]; then
    # note, /opt/orcle must be owned by oracle user
    mkOFNDir "/opt/oracle" "${log_file}" || return_code=2
fi

# Make run directory
mkOFNRUNDir "${ofnrun}" "${log_file}" || return_code=2

if [ ! -d "${ofndata}" ]; then
   mkOFNDir "${ofndata}" "${log_file}" || return_code=2
fi
if [ ! -d "${ofndata}/stage" ]; then
    mkOFNDir "${ofndata}/stage" "${log_file}" || return_code=2
fi

# get the OS version so we can pick the right PRMs
os_ver=$( /bin/grep '^VERSION_ID' /etc/os-release | /bin/tr -d '"' | /bin/cut -d . -f 1 | /bin/cut -d = -f 2 )
logMesg 0 "Detected OS Version: $os_ver" I "${log_file}"

# setup URL and RPM names for the DB Free packages
dbfpurl="https://yum.oracle.com/repo/OracleLinux/OL${os_ver}/appstream/x86_64/getPackage/${DBFPNAME}-${DBFPVER}.el${os_ver}.x86_64.rpm"
dbfurl="https://download.oracle.com/otn-pub/otn_software/db-free/${DBFNAME}-${DBFVER}.el${os_ver}.x86_64.rpm"

# try to install required RPMs
if instOFNRPM "${dbfpurl}" "${log_file}"; then
    if ! instOFNRPM "${dbfurl}" "${log_file}"; then
        return_code=2
    fi
else
    return_code=2
fi

# configure the database
# set a random password 16 characters long
password=$( /bin/tr -dc '#_$A-Za-z0-9' < /dev/urandom | /bin/head -c 16 )

logMesg 0 "Begining database configuration." I "${log_file}"
(echo "${password}"; echo "${password}";) | /etc/init.d/oracle-free-26ai configure >> "${log_file}" 2>&1
logMesg 0 "Check log file for database configuration issues." I "${log_file}"
logMesg 0 "Initial password set to: ${password}" I "${log_file}"

# setup Oracle user shell
ora_bashrc=/home/oracle/.bashrc
echo "# added by OFN script"   >> "${ora_bashrc}"
echo "export ORACLE_SID=FREE"  >> "${ora_bashrc}"
echo "export ORAENV_ASK=NO"  >> "${ora_bashrc}" 
echo "source /opt/oracle/product/26ai/dbhomeFree/bin/oraenv -s"  >> "${ora_bashrc}"
echo ""                        >> "${ora_bashrc}"

exit ${return_code}
#END
