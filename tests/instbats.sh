#!/bin/bash
# instbats.sh

base_dir="${HOME}/bats"
src_dir="${base_dir}/src"

ASERT_VER=2.1.0
SUP_VER=0.3.0
BATS_VER=1.10.0

[ ! -d "${base_dir}" ] && /bin/mkdir "${base_dir}" 
[ ! -d "${src_dir}" ] && /bin/mkdir "${src_dir}" 


https://github.com/bats-core/bats-assert/archive/refs/tags/v2.1.0.zip
https://github.com/bats-core/bats-support/archive/refs/tags/v0.3.0.zip
wget https://github.com/bats-core/bats-core/archive/refs/tags/v${BATS_VER}.zip -O "${src_dir}/bats.zip"
wget https://github.com/bats-core/bats-assert/archive/refs/tags/v${ASERT_VER}.zip -O "${src_dir}/asert.zip"
wget https://github.com/bats-core/bats-support/archive/refs/tags/v${SUP_VER}.zip -O "${src_dir}/support.zip"

unzip -q "${src_dir}/bats.zip" -d "${src_dir}"
unzip -q "${src_dir}/asert.zip" -d "${src_dir}"
unzip -q "${src_dir}/support.zip" -d "${src_dir}"


[ ! -d "${base_dir}/test_helper" ] && /bin/mkdir "${base_dir}/test_helper" 
[ ! -d "${base_dir}/test_helper/bats-assert" ] && /bin/mkdir "${base_dir}/test_helper/bats-assert" 
[ ! -d "${base_dir}/test_helper/bats-support" ] && /bin/mkdir "${base_dir}/test_helper/bats-support" 

mv "${src_dir}"/bats-assert*/* "${base_dir}/test_helper/bats-assert"
mv "${src_dir}"/bats-support*/* "${base_dir}/test_helper/bats-support"

bats_install=$( find "${src_dir}" -name install.sh )
[ -x "${bats_install}" ] && "${bats_install}" "${base_dir}"

echo "alias bats='${base_dir}/bin/bats'" >> ~/.bashrc

echo "BATS BASH shell script testing version $BATS_VER installed"
echo "logout and back in again to have your environment updated, or source .bashrc"




