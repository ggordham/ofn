#!/bin/bash
# ofn.sh

## Oracle (database) Free Now (OFN) scripts
## This is the primary script used to initiate all commands
## Additional helper scripts
##   ofn_bkup.sh   - backup, recovery, and replace PDB
##   ofn_setup.sh  
##   ofn_lib.sh
##   ofn.shlib     - shared functions for all scripts

# Internal settings
SCRIPTVER=1.0
SCRIPTNAME=$(basename "${BASH_SOURCE[0]}")
source "$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"/ofn.shlib



