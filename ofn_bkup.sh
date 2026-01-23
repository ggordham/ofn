#!/bin/bash
# ofn_bkup.sh

# Oracle (database) Free Now! (OFN) 
# script to deal with database backup and restores

# Internal settings
SCRIPTVER=1.0.0
SCRIPTNAME=$(basename "${BASH_SOURCE[0]}")
source "$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"/ofn.shlib
source "$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"/ofn_ora.shlib
PIDFILE="${SCRIPTNAME%.*}.pid"

# retun command line help information
function help_ofn_bkup {
  echo >&2
  echo "$SCRIPTNAME                                     " >&2
  echo "   used to backup and restore Oracle DB Free    " >&2
  echo "   version: $SCRIPTVER                          " >&2
  echo >&2                                              
  echo "Usage: $SCRIPTNAME [-h --debug --test ]         " >&2
  echo "--pdb      [PDB] defaults to FREEPDB1           " >&2
  echo "--dst      [ PATH ] path for backup files       " >&2
  echo "--type     [ rman | dp ] Backup tool to use     " >&2
  echo "--lvl      [ i | f | a ] for RMAN backup lvl    " >&2
  echo "            i = incremental f = full a = archive" >&2
  echo "  NOTE: above settings will default from config " >&2
  echo "        config file $CONF_FILE though you must  " >&2
  echo "        propvide the backup level.              " >&2
  echo "--debug    turn on debug mode                   " >&2
  echo "--test     turn on test mode, disable DBCA run  " >&2
  echo "--version | -v Show the script version          " >&2
  echo "-h         give this help screen                " >&2
}

#check command line options
function checkopt_ofn_bkup {

    #set defaults
    DEBUG=FALSE
    TEST=FALSE
    typeset -i badopt=0

    # shellcheck disable=SC2068
    my_opts=$(getopt -o hv --long help,debug,test,version,pdb:,type:,lvl:,dst: -n "$SCRIPTNAME" -- $@)
    if (( $? > 0 )); then
        (( badopt=1 ))
    else
        eval set -- "$my_opts"
        while true; do
            case $1 in
          "--help"|"-h") help_ofn_bkup                         #  help
                     exit 0;;
          "--pdb") dbpdb="$2"
                     shift 2;;
          "--type") bkuptype="$2"
                     shift 2;;
          "--lvl") bkuplvl="$2"
                     shift 2;;
          "--dst") bkupdst="$2"
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

# run an rman script
#    returns 6 if rman has non-zero value
#
function run_rman {

    local my_rman_script=$1
    local my_logfile="$2"
    local my_return_code=0
  
    # make RMAN output more readble for timestamps
    export NLS_DATE_FORMAT='YYYY-MM-DD HH24:MI:SS'
     
   if [ "$TEST" == "TRUE" ]; then
       logMesg 0 "TEST MODE: NOT running ${ORACLE_HOME}/bin/rman  @${my_rman_script} log=${my_logfile} append" I "${my_logfile}"
   else
       logMesg 0 "Running RMAN script ${my_rman_script}" I "${my_logfile}"
       "${ORACLE_HOME}"/bin/rman  "@${my_rman_script}" log="${my_logfile}" append >> /dev/null 2>&1
       my_return_code=$?
       logMesg 0 "RMAN return code: ${my_return_code}" I "${my_logfile}"
       # if rman returned non-zero then set error code.
       if (( my_return_code > 0 )); then 
           logMesg 6 "RMAN returned an ERROR!" E "NONE"
           my_return_code=$?
       fi
   fi
   
   # clean up rman script
    if [ "${TEST}" == "TRUE" ]; then
       logMesg 0 "TEST MODE: Retaining rman script at: ${my_rman_script}" I "${my_logfile}"
   else
       logMesg 0 "Removing RMAN script at ${my_rman_script}" I "${my_logfile}"
       [ -f "${my_rman_script}" ] && /bin/rm "${my_rman_script}" >> "${my_logfile}" 2>&1
   fi 

   return $my_return_code
  
}

# function to run rman backups
#
rmanbackup () {

    local my_bkuplvl=$1
    local my_logfile="$2"
  
    local my_rman_script
    local my_rman_tag
    local my_compress
    local my_section_size
    local my_filesperset=""

    # Generate tag and script names
    my_rman_tag="${ORACLE_SID}_${my_bkuplvl^^}_$( /bin/date '+%Y_%m_%d.%H_%M' )"
    my_rman_script="/tmp/backup_${ORACLE_SID}_${my_bkuplvl}.rman"
    logMesg 0 "Generating rman script at: ${my_rman_script}" I "${my_logfile}"

    # check if optional parameters are enabled
    [ "${bkupcomp^^}" == "T" ] && my_compress=" COMPRESSED"
    [ -n "${bkupsecsiz:-}" ] && my_section_size=" SECTION SIZE ${bkupsecsiz}"
    if [ -n "${bkupfilesperset:-}" ] && [[ "${bkupfilesperset}" =~ ^[0-9]+$ ]]; then my_filesperset=" FILESPERSET ${bkupfilesperset}"; fi

    echo "# Generated RMAN script from ${SCRIPTNAME} "    > "${my_rman_script}"
    echo "#  Date:  $(date '+%Y/%m/%d %H:%M:%S')       " >> "${my_rman_script}"
    echo "CONNECT TARGET / "                             >> "${my_rman_script}"
    echo "SHOW ALL; "                                    >> "${my_rman_script}"
    echo ""                                              >> "${my_rman_script}"
 
    echo "CONFIGURE CONTROLFILE AUTOBACKUP ON;"          >> "${my_rman_script}"
    echo "CONFIGURE CONTROLFILE AUTOBACKUP FORMAT FOR DEVICE TYPE DISK TO '${bkupdst}/%F'; " >> "${my_rman_script}"
    echo "CONFIGURE RETENTION POLICY TO RECOVERY WINDOW OF ${bkuprtn} DAYS;" >> "${my_rman_script}"
    echo "CONFIGURE ARCHIVELOG DELETION POLICY TO BACKED UP 1 TIMES TO DISK; " >> "${my_rman_script}"
    echo ""                                              >> "${my_rman_script}"

    # Begin the backup script part
    echo "SET ECHO ON"                                   >> "${my_rman_script}"
    echo ""                                              >> "${my_rman_script}"
    echo "RUN {"                                         >> "${my_rman_script}"
 
    echo "ALLOCATE CHANNEL DISK1 DEVICE TYPE DISK FORMAT '${bkupdst}/%U';" >> "${my_rman_script}"
    echo ""                                              >> "${my_rman_script}"

    case "${my_bkuplvl^^}" in
      "F")
        my_cmd="INCREMENTAL LEVEL 0 DATABASE";;
      "I")
        my_cmd="INCREMENTAL LEVEL 1 DATABASE";;
      "A")
        my_cmd="ARCHIVELOG ALL${my_filesperset} "
        echo "SQL 'ALTER SYSTEM ARCHIVE LOG CURRENT';" >> "${my_rman_script}"
        ;;
    esac

    echo "BACKUP AS${my_compress} BACKUPSET${my_section_size} ${my_cmd} TAG '${my_rman_tag}';" >> "${my_rman_script}"
    echo "BACKUP CURRENT CONTROLFILE;"                   >> "${my_rman_script}"
    echo ""                                              >> "${my_rman_script}"
    echo "# Cross check and delete expired or missing backups" >> "${my_rman_script}"
    echo "CROSSCHECK BACKUP;"                            >> "${my_rman_script}"
    echo "CROSSCHECK ARCHIVELOG ALL;"                    >> "${my_rman_script}"
    echo "DELETE NOPROMPT EXPIRED ARCHIVELOG ALL DEVICE TYPE DISK;" >> "${my_rman_script}"
    echo "DELETE NOPROMPT EXPIRED BACKUP DEVICE TYPE DISK;" >> "${my_rman_script}"
    echo ""                                              >> "${my_rman_script}"
    echo "DELETE NOPROMPT OBSOLETE DEVICE TYPE DISK;"    >> "${my_rman_script}"
    echo "DELETE NOPROMPT ARCHIVELOG ALL BACKED UP 1 TIMES TO DEVICE TYPE DISK;"    >> "${my_rman_script}"
    echo ""                                              >> "${my_rman_script}"
    echo "RELEASE CHANNEL DISK1;"                        >> "${my_rman_script}"
    echo "}" >> "${my_rman_script}"
    echo ""                                              >> "${my_rman_script}"
    echo "exit;"                                         >> "${my_rman_script}"

    # run the generated script
    run_rman "${my_rman_script}" "${my_logfile}"
    return $?
}

# function to check and possibly set control file retention
# Note retention needs to cover backup retntion period
#   EG if backup retention is 14 days, then this needs to be
#   one week farther to cover cleanup (so doing retention + 8)
#
chk_set_retention () {

  local my_setting="$(( bkuprtn + 8 ))"
  local my_value
  local my_sql
  local my_return_code=0

  logMesg 0 "Checking control_file_record_keep_time setting." I "${log_file}"
  my_sql="SELECT 'KEEP', value FROM v\$parameter WHERE name = 'control_file_record_keep_time';"
  my_value="$( callSQLPlus "${my_sql}" )"

  # if not higher then needed setting, we will change it
  if (( my_value < my_setting )); then
      logMesg 0 "control_file_record_keep_time set to low: ${my_value}" I "${log_file}"
      my_sql="ALTER SYSTEM SET control_file_record_keep_time=${my_setting} SCOPE=both;"
      my_value="$( callSQLPlus "${my_sql}" )"
      if (( my_value < 0 )); then
          logMesg 2 "control_file_record_keep_time could not be adjusted! " E "${log_file}"
          my_return_code=1
      else
          logMesg 0 "control_file_record_keep_time adjusted to: ${my_setting}" I "${log_file}"
          logMesg 0 "control_file_record_keep_time adjusted to: ${my_setting}" I "${log_file}"
      fi
  else
      logMesg 0 "control_file_record_keep_time set correctly: ${my_value}" I "${log_file}"
  fi

  return ${my_return_code}
}


# function to run rman cleanup
#
rmancleanup () {

    local my_rman_script
    my_rman_script="/tmp/backup_${DB_UNIQUE}_cleanup.rman"

    echo "# Generated RMAN script from ${SCRIPTNAME} "    > "${my_rman_script}"
    echo "#  Date:  $(date '+%Y/%m/%d %H:%M:%S')       " >> "${my_rman_script}"
    echo "CONNECT TARGET / "                             >> "${my_rman_script}"
    echo "SHOW ALL; "                                    >> "${my_rman_script}"
    echo ""                                              >> "${my_rman_script}"
    # Begin the cleanup script
    echo "SET ECHO ON"                                   >> "${my_rman_script}"
    echo ""                                              >> "${my_rman_script}"
    echo "RUN {"                                         >> "${my_rman_script}"
 
    echo "ALLOCATE CHANNEL DISK1 DEVICE TYPE DISK FORMAT '${bkupdst}/%U';" >> "${my_rman_script}"
    echo "ALLOCATE CHANNEL DISK2 DEVICE TYPE DISK FORMAT '${bkupdst}/%U';" >> "${my_rman_script}"
    echo ""                                              >> "${my_rman_script}"

    echo "# Cross check and delete expired or missing backups" >> "${my_rman_script}"
    echo "CROSSCHECK BACKUP;"                            >> "${my_rman_script}"
    echo "CROSSCHECK ARCHIVELOG ALL;"                    >> "${my_rman_script}"
    echo "DELETE NOPROMPT EXPIRED ARCHIVELOG ALL DEVICE TYPE DISK;" >> "${my_rman_script}"
    echo "DELETE NOPROMPT EXPIRED BACKUP DEVICE TYPE DISK;" >> "${my_rman_script}"
    echo ""                                              >> "${my_rman_script}"
    echo "DELETE NOPROMPT OBSOLETE DEVICE TYPE DISK;"    >> "${my_rman_script}"
    echo "DELETE NOPROMPT ARCHIVELOG ALL BACKED UP 1 TIMES TO DEVICE TYPE DISK;"    >> "${my_rman_script}"
    echo ""                                              >> "${my_rman_script}"
    echo "RELEASE CHANNEL DISK1;"                        >> "${my_rman_script}"
    echo "RELEASE CHANNEL DISK2;"                        >> "${my_rman_script}"
    echo "}" >> "${my_rman_script}"
    echo ""                                              >> "${my_rman_script}"
    echo "exit;"                                         >> "${my_rman_script}"

    # run the generated script
    run_rman "${my_rman_script}"
    return $?
}

############################################################################################
# start here

OPTIONS=$@
return_code=0

# verify that we are oracle to run this script
if [ "x$USER" != "xoracle" ];then logMesg 1 "You must be logged in as oracle to run this script" E "NONE";  exit 1; fi

if checkopt_ofn_bkup "$OPTIONS" ; then

    # check settings, otherwise lookup default setting from config file
    if [ -z "${dbpdb:-}" ]; then dbpdb=$( cfgGet "$CONF_FILE" dbpdb ); fi
    if [ -z "${bkuptype:-}" ]; then bkuptype=$( cfgGet "$CONF_FILE" bkuptype ); fi
    if [ -z "${bkupdst:-}" ]; then bkupdst=$( cfgGet "$CONF_FILE" bkupdst ); fi

     # check for required settings / command line parametes
    if ! inList "RMAN DP" "${bkuptype^^}"; then
        logMesg 1 "Invalid backup type: ${bkuptype}" E "NONE"
        return_code=$?
    fi
    if [ "${bkuptype^^}" == "RMAN" ] && [ -z "${bkuplvl:-}" ]; then
        logMesg 1 "Missing required paramter --lvl" E "NONE"
        return_code=$?
    fi
    if [ "${bkuptype^^}" == "RMAN" ] && ! inList "I F A" "${bkuplvl^^}"; then
        logMesg 1 "Invalid backup level or not provided: ${bkuplvl}" E "NONE"
        return_code=$?
    fi
    # dump out if we are not safe to continue
    (( return_code > 0 )) && exit $return_code
 
    # setup logfile
    log_file="${ofnlog}/db-backup-$( /bin/date +%Y%m%d-%H%M%S ).log"

    # start script
    logMesg 0 "$SCRIPTNAME start" I "${log_file}"
    if [ "$DEBUG" == "TRUE" ]; then logMesg 0 "DEBUG Mode Enabled!" I "${log_file}" ; fi
    if [ "$TEST" == "TRUE" ]; then logMesg 0 "TEST Mode Enabled, commands will not be run." I "${log_file}" ; fi

    # check that no other backup is runnig
    check_pid "${ofnrun}/${PIDFILE}" "${log_file}"|| exit 2

    # if test mode provide some detaild information
    if [ "$TEST" == "TRUE" ]; then logMesg 0 "PDB: $dbpdb" I "${log_file}" ; fi
    if [ "$TEST" == "TRUE" ]; then logMesg 0 "Backup Type: $bkuptype" I "${log_file}" ; fi
    if [ "$TEST" == "TRUE" ]; then logMesg 0 "Backup Dest: $bkupdst" I "${log_file}" ; fi
    if [ "$TEST" == "TRUE" ]; then logMesg 0 "Backup Level: $bkuplvl" I "${log_file}" ; fi

    # load optional settings from configuration file
    bkuprtn=$( cfgGet "$CONF_FILE" bkuprtn )
    bkupcomp=$( cfgGet "$CONF_FILE" bkupcomp )
    bkupsecsiz=$( cfgGet "$CONF_FILE" bkupsecsiz )
    bkupfilesperset=$( cfgGet "$CONF_FILE" bkupfilesperset )
    if [ "$TEST" == "TRUE" ]; then logMesg 0 "Backup Retention Days: $bkuprtn" I "${log_file}" ; fi
    if [ "$TEST" == "TRUE" ]; then logMesg 0 "Backup Compression: $bkupcomp" I "${log_file}" ; fi
    if [ "$TEST" == "TRUE" ]; then logMesg 0 "Backup Section Size: $bkupsecsiz" I "${log_file}" ; fi
    if [ "$TEST" == "TRUE" ]; then logMesg 0 "Backup Files Per Set: $bkupfilesperset" I "${log_file}" ; fi

    # Verify that Oracle Free is installed
    if ! chkOraInst ; then exit 3; fi
 
    # set Oracle environment, check database status
    setOraenv
    if (( return_code < 1 )) && chkOraDBUp "${dbpdb}" ; then

        # Check control file record keep
        chk_set_retention

        # get database log mode
        sql="SELECT 'KEEP', log_mode FROM v\$database;"
        dblogmode="$( callSQLPlus "${sql}" )"
        logMesg 0 "Database log_mode:  ${dblogmode}" I "${log_file}"

        # Check destination directory
        if [ -d "${bkupdst}" ] || /bin/mkdir -p "${bkupdst}" ; then
       
            # make decision on backup type
            case "${bkuptype^^}" in
              "RMAN")
                if [ "${dblogmode}" == "ARCHIVELOG" ]; then
                    if [ "${bkuplvl^^}" == "C" ]; then
                        rmancleanup
                        return_code=$?
                    else
                        rmanbackup "${bkuplvl^^}" "${log_file}"
                        return_code=$?
                    fi
                else
                    logMesg 4 "Database is not in archivelog mode, can not backup with rman." E "${log_file}"
                    return_code=$?
                fi
                ;;
              "DP")
                logMesg 1 "Datapump backup not implimented yet." E "${log_file}"
                return_code=$?
                ;;
            esac
        else # check backup destination
            logMesg 2 "Could not find or create backup destination: $bkupdst" E "${log_file}"
            return_code=$?
        fi;
    else
        # database not available
        logMesg 2 "Database $ORACLE_SID is not available." E "${log_file}"
        return_code=$?
    fi  # chkOraDBUp


    # clean pid file
    logMesg 0 "Final return code: ${return_code}" I "${log_file}"
    logMesg 0 "End ${SCRIPTNAME} cleaning pidfile ${PIDFILE}" I "${log_file}"
    [ -f "${PIDFILE}" ] && /bin/rm "${PIDFILE}" >> "${log_file}" 2>&1
   # compress log file when done
   [ -f "${log_file}" ] && /bin/gzip "${log_file}"
   logMesg 0 "Logfile at: ${log_file}.gz" I "NONE"

else
    echo "ERROR - invalid command line parameters" >&2
    return_code=1
fi  # checkopt_ofn_bkup

exit $return_code
#END

