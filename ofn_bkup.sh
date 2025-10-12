#!/bin/bash
# ofn_bkup.sh

# Oracle (database) Free Now! (OFN) 
# script to deal with database backup and restores

# Internal settings
SCRIPTVER=1.0.0
SCRIPTNAME=$(basename "${BASH_SOURCE[0]}")
source "$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"/ofn.shlib
PIDFILE="/${SCRIPTNAME%.*}.pid"

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
function checkopt_oraDBCA {

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
                     exit 1;;
          "--pdb") dbpdb="$2"
                     shift 2;;
          "--type") bkuptype="$2"
                     shift 2;;
          "--lvl") bkuplvl="$2"
                     shift 2;;
          "--dst") bkupdst="$2"
                     shift 2;;
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

  return $badopt
}

# run an rman script
#    returns 6 if rman has non-zero value
#
function run_rman {

    local my_rman_script=$1
    local my_logfile
    local my_return_code=0
    my_logfile="${ofnlog}/${my_rman_script}.$( /bin/date '+%Y%m%d%H%M' ).log"
  
    # make RMAN output more readble for timestamps
    export NLS_DATE_FORMAT='YYYY-MM-DD HH24:MI:SS'
     
   if [ "$TEST" == "TRUE" ]; then
       logMesg 0 "TEST MODE: NOT running ${ORACLE_HOME}/bin/rman  @${my_rman_script} log=${my_logfile} append" I "NONE"
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
       logMesg 0 "TEST MODE: Retaining rman script at: ${my_rman_script}" I "NONE"
   else
       logMesg 0 "Removing RMAN script at ${my_rman_script}" I "NONE"
       [ -f "${my_rman_script}" ] && /bin/rm "${my_rman_script}" >> "${my_logfile}" 2>&1
   fi 

   # compress log file when done
   [ -f "${my_logfile}" ] && /bin/gzip "${my_logfile}"
   logMesg "RMAN log file at: ${my_logfile}" I "NONE"

   return $my_return_code
  
}

# function to run rman backups
#
rmanbackup () {

    local my_bkuplvl=$?
  
    local my_rman_script
    local my_rman_tag
    local my_compress
    local my_section_sie
    local my_filesperset

    # Generate tag and script names
    my_rman_tag="${ORACLE_SID}_${my_bkuplvl^^}_$( /bin/date '+%Y_%m_%d.%H_%M' )"
    my_rman_script="/tmp/backup_${DB_UNIQUE}_${my_bkuplvl}.rman"

    # check if optional parameters are enabled
    [ "${bkupcomp^^}" == "T" ] && my_compress=" COMPRESSED"
    [ -n "${bkupsecsiz:-}" ] && my_section_size=" SECTION SIZE ${SECTION_SIZE}"
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
    echo "ALLOCATE CHANNEL DISK2 DEVICE TYPE DISK FORMAT '${bkupdst}/%U';" >> "${my_rman_script}"
    echo ""                                              >> "${my_rman_script}"

    case "${my_bkuplvl^^}" in
      "F")
        my_cmd="INCREMENTAL LEVEL 0 DATABASE";;
      "I")
        my_cmd="INCREMENTAL LEVEL 1 DATABASE";;
      "A")
        my_cmd="ARCHIVELOG ALL${my_filesperset} ";;
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
    echo "# Delete backups no longer needed for retention of ${RETENTION_DAYS} days" >> "${my_rman_script}"
    echo "DELETE NOPROMPT OBSOLETE DEVICE TYPE DISK;"    >> "${my_rman_script}"
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
    echo "# Delete backups no longer needed for retention of ${RETENTION_DAYS} days" >> "${my_rman_script}"
    echo "DELETE NOPROMPT OBSOLETE DEVICE TYPE DISK;"    >> "${my_rman_script}"
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

# verify that we are oracle to run this script
if [ "x$USER" != "xoracle" ];then logMesg 1 "You must be logged in as oracle to run this script" E "NONE";  exit 1; fi

if checkopt_ofn_bkup "$OPTIONS" ; then

    # Verify that Oracle Free is installed
    if ! chkOraIns ; then exit 1; fi
    
    logMesg 0 "$SCRIPTNAME start" I "NONE"
    if [ "$DEBUG" == "TRUE" ]; then logMesg 0 "DEBUG Mode Enabled!" I "NONE" ; fi
    if [ "$TEST" == "TRUE" ]; then logMesg 0 "TEST Mode Enabled, commands will not be run." I "NONE" ; fi
    # check that no other backup is runnig
    check_pid "${PIDFILE}" && exit 2

    # check settings, otherwise lookup default setting from config file
    if [ -z "${dbpdb:-}" ]; then dbpdb=$( cfgGet "$CONF_FILE" dbpdb ); fi
    if [ -z "${bkuptype:-}" ]; then bkuptype=$( cfgGet "$CONF_FILE" bkuptype ); fi
    if [ -z "${bkupdst:-}" ]; then bkupdst=$( cfgGet "$CONF_FILE" bkupdst ); fi

    # if test mode provide some detaild information
    if [ "$TEST" == "TRUE" ]; then logMesg 0 "PDB: $dbpdb" I "NONE" ; fi
    if [ "$TEST" == "TRUE" ]; then logMesg 0 "Backup Type: $bkuptype" I "NONE" ; fi
    if [ "$TEST" == "TRUE" ]; then logMesg 0 "Backup Dest: $bkupdst" I "NONE" ; fi
    if [ "$TEST" == "TRUE" ]; then logMesg 0 "Backup Level: $bkuplvl" I "NONE" ; fi

    # load optional settings from configuration file
    bkuprtn=$( cfgGet "$CONF_FILE" bkuprtn )
    bkupcomp=$( cfgGet "$CONF_FILE" bkupcomp )
    bkupsecsiz=$( cfgGet "$CONF_FILE" bkupsecsiz )
    bkupfilesperset=$( cfgGet "$CONF_FILE" bkupfilesperset )
    if [ "$TEST" == "TRUE" ]; then logMesg 0 "Backup Retention Days: $bkuprtn" I "NONE" ; fi
    if [ "$TEST" == "TRUE" ]; then logMesg 0 "Backup Compression: $bkupcomp" I "NONE" ; fi
    if [ "$TEST" == "TRUE" ]; then logMesg 0 "Backup Section Size: $bkupsecsiz" I "NONE" ; fi
    if [ "$TEST" == "TRUE" ]; then logMesg 0 "Backup Files Per Set: $bkupfilesperset" I "NONE" ; fi

    # check for required settings
    if ! inlist "RMAN DP" ${bkuptype^^}; then
        logMsg 1 "Invalid backup type: ${bkuptype}" E "NONE"
        return_code=$?
    fi
    if [ "${bkuptype^^}" == "RMAN" ] && ! inList "I F A" "${bkuplvl^^}"; then
        logMsg 1 "Invalid backup level or not provided: ${bkuplvl}" E "NONE"
        return_code=$?
    fi

    # set Oracle environment, check database status
    setOraenv
    if (( return_code < 0 )) && chkOraDBUp "${dbpdb}" ; then

        # Check destination directory
        if [ -d "${bkupdst}" ] && /bin/mkdir -p "${bkupdst}" ; then
       
            # make decision on backup type
            case "${bkuptype^^}" in
              "RMAN")
                if [ "${dblogmode}" == "ARCHIVELOG" ]; then
                    if [ "${bkuplvl^^}" == "C" ]; then
                        rmancleanup
                        return_code=$?
                    else
                        rmanbackup "${bkuplvl^^}"
                        return_code=$?
                    fi
                else
                    logMesg 4 "Database is not in archivelog mode, can not backup with rman." E "NONE"
                    return_code=$?
                fi
                ;;
              "DP")
                logMesg 1 "Datapump backup not implimented yet." E "NONE"
                return_code=$?
                ;;
            esac
        else # check backup destination
            logMesg 3 "Could not find or create backup destination: $bkupdst" E "NONE"
            return_code=$?
        fi;
    else
        # database not available
        return_code=2
    fi  # chkOraDBUp


    # clean pid file
    [ -f "${PIDFILE}" ] && /bin/rm "${PIDFILE}"

else
    echo "ERROR - invalid command line parameters" >&2
    return_code=1
fi  # checkopt_ofn_bkup

exit $return_code
#END

