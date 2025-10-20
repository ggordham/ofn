#!/bin/bash

target=$1
install_dir=/opt/ofn
inst_user=root
own_user=54321
own_grp=54321

file_list="../ofn.sh ../ofn_bkup.sh ../ofn_cron.sh ../ofn_inst.sh"
file_list="${file_list} ../ofn.shlib ../ofn_ora.shlib ../ofn.conf"
file_list="${file_list} ofn_bkup.bats instbats.sh"

# check the install server
chk_srvr=$( ssh "${inst_user}"@"${target}" hostname -s )

if [ "${chk_srvr}" == "${target}" ]; then

    ssh "${inst_user}"@"${target}" "[ ! -d ${install_dir} ] && /bin/mkdir ${install_dir}"

    for file in ${file_list}; do
        scp "${file}" "${inst_user}"@"${target}":"${install_dir}"
    done;

    ssh "${inst_user}"@"${target}" "/bin/chmod +x ${install_dir}/*.sh"
    ssh "${inst_user}"@"${target}" "/bin/chown ${own_user} ${install_dir}/ofn*"
    ssh "${inst_user}"@"${target}" "/bin/chgrp ${own_grp} ${install_dir}/ofn*"
    
else
    echo "ERROR! target server $target not detected, check: $chk_srvr" >&2
fi

# END
