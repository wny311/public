#!/bin/bash
mkdir -p /root/sealos
cat sealos |xargs wget
mv sealos_4.3.3_linux_amd64.tar.gz ../
cd ..
tar zxvf sealos_4.3.3_linux_amd64.tar.gz -C sealos
cd sealos
mv image-cri-shim lvscare sealos sealctl /usr/local/bin/
