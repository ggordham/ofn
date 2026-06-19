#!/bin/bash
# ofn_utils.sh

# Oracle (database) Free Now! (OFN) 
# script to cover a bunch of misc DB actions or configurations
#
# TODO 
#  

# Internal settings
SCRIPTVER=1.0.0
SCRIPTNAME=$(basename "${BASH_SOURCE[0]}")
source "$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"/ofn.shlib
source "$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"/ofn_ora.shlib

# global settings
SCRIPT_MODES="noarch arch set reset show showset"

# retun command line help information
function help_ofn_utils {
  echo >&2
  echo "$SCRIPTNAME                                     " >&2
  echo "   bunch of database actions or configuarations " >&2
  echo "   version: $SCRIPTVER                          " >&2
  echo >&2                                              
  echo "Usage: $SCRIPTNAME [-h --debug --test ]         " >&2
  echo "--util [ show | showset | set | reset | [no]arch ]" >&2
  echo "       show - show a specific DB parameter      " >&2
  echo "       showset - show all modified parameters   " >&2
  echo "       set - set a database paramter            " >&2
  echo "       reset - reset a database paramter        " >&2
  echo "       [no]arch - change archivelog mode        " >&2
  echo "                                                " >&2
  echo "--parm <db_parm> DB Parameter to set or show    " >&2
  echo "--val  <value>  Value to set paramter to        " >&2
  echo "  NOTE: Values may need to be quoted to work    " >&2
  echo "--com  <value>  optional comment for parameter  " >&2
  echo "--debug    turn on debug mode                   " >&2
  echo "--test     turn on test mode, disable DBCA run  " >&2
  echo "--version | -v Show the script version          " >&2
  echo "-h         give this help screen                " >&2
}

#check command line options
function checkopt_ofn_utils {

    #set defaults
    DEBUG=FALSE
    TEST=FALSE
    typeset -i badopt=0

    # shellcheck disable=SC2068
    my_opts=$(getopt -o hv --long help,debug,test,version,util:,parm:,val:,com: -n "$SCRIPTNAME" -- $@)
    if (( $? > 0 )); then
        (( badopt=1 ))
    else
        eval set -- "$my_opts"
        while true; do
            case $1 in
          "--help"|"-h") help_ofn_utils                        #  help
                     exit 0;;
          "--util") ofn_util="$2"
                     shift 2;;
          "--parm") db_parm="$2"
                     shift 2;;
          "--val") db_parm_val="$2"
                     shift 2;;
          "--com") db_parm_com="$2"
                     shift 2;;
          "--debug") DEBUG=TRUE                         # debug mode
                     echo "DEBUG Mode Enabled" 
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

  return $badopt
}

# show_parm [ parm_name | SHOWSET ]
#
# show a database paramter or all set parameters
function show_parm () {

    local my_parm=$1
    local my_return=0
    local my_filter

    # for parameters we want to be connected to container DB
    unset ORACLE_PDB_SID

    # check if we are showing all set paramters
    if [ "${my_parm}" == "SHOWSET" ]; then
        my_filter="  AND ( p.ismodified = 'TRUE' or s.isspecified = 'TRUE' );"
    else
        my_filter="  AND p.name = lower('${my_parm}');"
    fi

    # show the parameter
    "${ORACLE_HOME}/bin/sqlplus" -s /nolog  <<!EOF 
          WHENEVER sqlerror EXIT sql.sqlcode;
          CONNECT / AS SYSDBA
          SET LINESIZE 120
          SET PAGESIZE 100
          COLUMN parameter FORMAT A25
          COLUMN in_memory FORMAT A25
          COLUMN spfile_set FORMAT A25
          COLUMN update_comment FORMAT A25

          SELECT p.name as parameter, p.value as in_memory, s.value as spfile_set, s.isspecified as in_spfile,
                 s.update_comment
            FROM v\$spparameter s, v\$parameter p
            WHERE s.con_id = p.con_id
              AND s.name = p.name
              ${my_filter}
          exit
!EOF
    my_return=$?

    return $my_return
}

# set_parm <parm_name> <parm_value> <comment>
#
# set a parameter
function set_parm () {

    local my_parm=$1
    local my_val=$2
    local my_comment=$3
    local my_return=0

    # for parameters we want to be connected to container DB
    unset ORACLE_PDB_SID

    # create a comment
    my_comment="Set by OFN $( /bin/date +%Y%m%d ) ${my_comment:-}"

    # set the parameter
    "${ORACLE_HOME}/bin/sqlplus" -s /nolog  <<!EOF 
          WHENEVER sqlerror EXIT sql.sqlcode;
          CONNECT / AS SYSDBA
          ALTER SYSTEM SET ${my_parm}=${my_val} COMMENT='${my_comment}' SCOPE=both;

          exit
!EOF
    my_return=$?

    return $my_return
}

# reset_parm <parm_name>
#
# reset a parameter
function reset_parm () {

    local my_parm=$1
    local my_return=0

    # for parameters we want to be connected to container DB
    unset ORACLE_PDB_SID

    # set the parameter
    "${ORACLE_HOME}/bin/sqlplus" -s /nolog  <<!EOF 
          WHENEVER sqlerror EXIT sql.sqlcode;
          CONNECT / AS SYSDBA
          ALTER SYSTEM RESET ${my_parm}=${my_val} SCOPE=both;

          exit
!EOF
    my_return=$?

    return $my_return
}

# set_archive [ ARCHIVELOG | NOARCHIVELOG ] <arch_path>
#
# Change database archivelog mode 
function set_archive () {

    local my_arch_mode=$1
    local my_arch_dest=$2
    local my_db_mode
    local my_return_code


    # check mode
    case "${my_arch_mode^^}" in
        "ARCHIVELOG")
          set_parm log_archive_dest "${my_arch_dest}" "enable archive log mode"
          [ -d "${my_arch_dest}" ] && /bin/mkdir -p "${my_arch_dest}"
          ;;
        "NOARCHIVELOG")
          reset_parm log_archive_dest
          ;;
        *)
           logMesg 255 "Internal error, invalid arch_mode in set_archive." E "NONE"
           return 255
           ;;
    esac

    # check the database open mode
    unset ORACLE_PDB_SID
    my_db_mode=$( callSQLPlus "SELECT 'KEEP', open_mode FROM v\$database;" )
    logMesg 0 "Database open_mode:  ${my_db_mode}" I "NONE"

    case "${my_db_mode}" in
        "READ WRITE")
            logMesg 0 "Shutting down database" I "NONE"
            shutdown_db immediate
            my_return_code=$?
            if (( my_return_code < 1 )); then
                logMesg 0 "Mounting database" I "NONE"
                startup_db mount
                my_return_code=$?
            else
                logMesg ${my_return_code} "Database could not be shutdown, need manual intervention" E "NONE"
            fi
            ;;
        "READ ONLY")
            logMesg 0 "Shutting down database" I "NONE"
            shutdown_db immediate
            my_return_code=$?
            if (( my_return_code < 1 )); then
                logMesg 0 "Mounting database" I "NONE"
                startup_db mount
                my_return_code=$?
            else
                logMesg ${my_return_code} "Database could not be shutdown, need manual intervention" E "NONE"
            fi
            ;;
        "MOUNTED")
            logMesg 0 "Database in mount mode already"  I "NONE"
            ;;
        *)
            logMesg 3 "Database mode incorrect, needs manual intervention" E "NONE"
            my_return_code=$?
            ;;
    esac

    # if the mount mode is correct continue to change settings
    if (( my_return_code < 1 )); then
        logMesg 0 "Switching database to archivelog mode."  I "NONE"
        callSQLPlus "ALTER DATABASE ${my_arch_mode^^};"
        callSQLPlus "ALTER DATABASE OPEN;"
        callSQLPlus "ALTER SYSTEM ARCHIVELOG CURRENT;"
        my_db_mode=$( callSQLPlus "SELECT 'KEEP', open_mode FROM v\$database;" )
        my_log_mode=$( callSQLPlus "select 'KEEP', log_mode FROM v\$database;" )
        logMesg 0 "DB open mode now: ${my_db_mode}"  I "NONE"
        logMesg 0 "DB log mode now: ${my_log_mode}"  I "NONE"
        
    fi

    return $my_return_code

}

############################################################################################
# start here

OPTIONS=$@
return_code=0

# verify that we are oracle to run this script
if [ "x$USER" != "xoracle" ];then logMesg 1 "You must be logged in as oracle to run this script" E "NONE";  exit 1; fi

if checkopt_ofn_utils "$OPTIONS" ; then

    # check that a utility mode has been provided
    if [ -z "${ofn_util:-}" ]; then logMesg 1 "You must provide a --util paramter" E "NONE"; exit 1; fi

    # start script
    logMesg 0 "$SCRIPTNAME start" I "NONE"
    if [ "$DEBUG" == "TRUE" ]; then logMesg 0 "DEBUG Mode Enabled!" I "${log_file}" ; fi
    if [ "$TEST" == "TRUE" ]; then logMesg 0 "TEST Mode Enabled, commands will not be run." I "${log_file}" ; fi

    # check for required settings / command line parametes
    if ! inList "${SCRIPT_MODES^^}" "${ofn_util^^}"; then
        logMesg 1 "Invalid utility type: ${ofn_util}" E "NONE"
        return_code=$?
        exit $return_code
    fi
 
    # Verify that Oracle Free is installed
    if ! chkOraInst ; then exit 3; fi

    # set Oracle environment, check database status
    setOraenv
    dbpdb=$( cfgGet "$CONF_FILE" dbpdb )
    if (( return_code < 1 )) && chkOraDBUp "${dbpdb}" ; then

        case "${ofn_util^^}" in
            "SHOW")
                show_parm "${db_parm}"
                return_code=$?
                ;;
            "SHOWSET")
                show_parm SHOWSET
                return_code=$?
                ;;
            "SET")
                logMesg 0 "Setting paramter ${db_parm} to value ${db_parm_val}" I "NONE"
                set_parm "${db_parm}" "${db_parm_val}" "${db_parm_com}"
                return_code=$?
                ;;
            "RESET")
                logMesg 0 "RE-Setting paramter ${db_parm} to value ${db_parm_val}" I "NONE"
                reset_parm "${db_parm}"
                return_code=$?
                ;;
            "NOARCH")
                logMesg 0 "Changing database to NOARCHIVE log mode" I "NONE"
                set_archive NOARCHIVELOG
                return_code=$?
                ;;
            "ARCH")
                logMesg 0 "Changing database to ARCHIVE log mode" I "NONE"
                set_archive ARCHIVELOG "${db_arch}"
                return_code=$?
                ;;
            *)
                logMesg 1 "Invalid utility type: ${ofn_util}" E "NONE"
                return_code=$?
                ;;
        esac


    else
        # database not available
        logMesg 2 "Database $ORACLE_SID is not available." E "${log_file}"
        return_code=$?
    fi  # chkOraDBUp


else
    echo "ERROR - invalid command line parameters" >&2
    return_code=1
fi  # checkopt_ofn_utils

exit $return_code
#END

