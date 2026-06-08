#!/bin/bash
# ofn_tera_storag.sh

# Oracle (database) Free Now! (OFN) 
# script used during automated testing to setup storage

# verify that we are root to run this script
if [ "x$USER" != "xroot" ];then echo "You must be logged in as root to run this script"; exit 1; fi

# comma seperated list of disks to format
# <mount>:<device>
disk_list=/opt/oracle:/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_drive-scsi1

# defualt filesystem settings
fs_type=xfs
fs_mount_xfs=defaults,noatime,nodiratime,logbufs=8,logbsize=256k,largeio,inode64,swalloc,allocsize=512m,_netdev 0 0

# OS version
os_ver=$( /bin/grep '^VERSION_ID' /etc/os-release | /bin/tr -d '"' | /bin/cut -d . -f 1 | /bin/cut -d = -f 2 )
 
# setup local disks
for disk in $( echo "${disk_list}" | /bin/tr "," " " ); do
    mount=$( echo "${disk}" | /bin/cut -d : -f 1 )
    disk=$( echo "${disk}" | /bin/cut -d : -f 2 )
    label=$( /bin/basename "$mount" )
    echo "Setting up local storage: fs: $mount disk: $disk "
    if [ -b "${disk}" ]; then
        /bin/mkdir -p "${mount}"
        /bin/chmod 755 "${mount}"
        /sbin/mkfs.${fs_type} -L "${label}" "${disk}"
        echo "LABEL=${label} ${mount} ${fs_type} defaults 0 0" >> /etc/fstab
        if (( os_ver > 7 )); then /usr/bin/systemctl daemon-reload; fi
        /bin/mount "${mount}"
    else
        echo "Could not find block device:$disk "
        exit 1
    fi
done

# END 
