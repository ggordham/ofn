#!/usr/bin/env bats

# BATS test file for ofn_bkup.sh shell script
# NOTE:
#

# static locations
script_file=ofn_bkup.sh
conf_file=ofn.conf
install_dir=/opt/ofn
test_dir=$HOME/test

# this is run before all tests once
setup_file () {
echo " S Test Name                                                                              RC " >&3
echo " - -------------------------------------------------------------------------------------- ---" >&3

}

# Load a library from the `${BATS_TEST_DIRNAME}/test_helper' directory.
#
# Globals:
#   none
# Arguments:
#   $1 - name of library to load
# Returns:
#   0 - on success
#   1 - otherwise
load_lib() {
  local name="$1"
  load "${BATS_ROOT}/test_helper/${name}/load"
}

load_lib bats-assert
load_lib bats-support

# setup is run before each test is execute
setup () {

  # Allways return no error
  return 0
}

# Clean up after each test
teardown () {

  # cleanup rman scripts
  [ -f /tmp/backup*.rman ] && /bin/rm /tmp/backup*.rman

  # put config file back
  [ -f "${install_dir}/${conf_file}.tmp" ] && mv "${install_dir}/${conf_file}.tmp" "${install_dir}/${conf_file}" 
  # Allways return no error
  return 0
}

# Test - help mode
@test "${script_file} - help mode                                                            (0)" {

  run ${install_dir}/${script_file} -h
  assert_success
  run ${install_dir}/${script_file} --help
  assert_success
}

# Test - version mode
@test "${script_file} - version mode                                                         (0)" {

  run ${install_dir}/${script_file} -v
  assert_success
  run ${install_dir}/${script_file} --version
  assert_success
}

# Test - no parameters passed
@test "${script_file} - no parameters passed                                                 (1)" {

  run ${install_dir}/${script_file} 
  assert_failure 1
}

# Test - DEBUG mode                            
@test "${script_file} - DEBUG mode                                                           (1)" {

  script_parm="--debug --lvl x"
  run ${install_dir}/${script_file} ${script_parm}
  assert_failure 1
  assert_output --partial 'DEBUG Mode Enabled'
}

# Test - TEST mode                            
@test "${script_file} - TEST mode                                                            (0)" {

  script_parm="--test --lvl a"
  run ${install_dir}/${script_file} ${script_parm}
  assert_success 
  assert_output --partial 'TEST Mode Enabled'
}

# Test - invalid parameter passed
@test "${script_file} - invalid parameter passed                                             (1)" {

  script_parm="--invalid"
  run ${install_dir}/${script_file} ${script_parm}
  assert_failure 1
  assert_output --partial 'ERROR - invalid command line parameters'
}

# Test - parameter but not required parameter
@test "${script_file} - missing required parameter                                           (1)" {

  script_parm="--pdb FREEPDB1"
  run ${install_dir}/${script_file} ${script_parm}
  assert_failure 1
  assert_output --partial 'Missing required paramter --lvl'
}

# Test - required parameter no value
@test "${script_file} - rman backup missing level value                                      (1)" {

  script_parm="--lvl "
  run ${install_dir}/${script_file} ${script_parm}
  assert_failure 1
  assert_output --partial 'requires an argument'
}

# Test - invalid bckup type
@test "${script_file} - invalid type parameter                                               (1)" {

  script_parm="--type xx"
  run ${install_dir}/${script_file} ${script_parm}
  assert_failure 1
  assert_output --partial 'Invalid backup type'
}

# Test - data pump type not supported yet
@test "${script_file} - data pump type not supported yet                                     (1)" {

  script_parm="--type dp"
  run ${install_dir}/${script_file} ${script_parm}
  assert_failure 1
  assert_output --partial 'Datapump backup not implimented yet'
}

# Test - rman backup level incorrect
@test "${script_file} - rman backup level incorrect value                                    (1)" {

  script_parm="--type rman --lvl x"
  run ${install_dir}/${script_file} ${script_parm}
  assert_failure 1
  assert_output --partial 'Invalid backup level or not provided'
}

# Test - config file does not exist
@test "${script_file} - config file does not exist                                           (1)" {

  [ -f "${install_dir}/${conf_file}" ] && mv "${install_dir}/${conf_file}" "${install_dir}/${conf_file}.tmp" 
  script_parm="--lvl a"
  run ${install_dir}/${script_file} ${script_parm}
  assert_failure 1
  assert_output --partial 'Could not load configuration file'
  
}

# Test - backup destinstination does not exist / cannot create
@test "${script_file} - backup destination does not exist / cannot create                    (2)" {

  script_parm="--type rman --lvl a --dst /backup_does_not_exist"
  run ${install_dir}/${script_file} ${script_parm}
  assert_failure 2
  assert_output --partial 'Could not find or create backup destination'
  
}

