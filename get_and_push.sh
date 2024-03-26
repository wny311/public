#!/bin/bash
set -x 
set -o pipefail
set -e
set -u

docker login registry.cn-beijing.aliyuncs.com -u wny311 -p Aitian1108
docker login registry-vpc.cn-beijing.aliyuncs.com -u wny311 -p Aitian1108
docker login registry-internal.cn-beijing.aliyuncs.com -u wny311 -p Aitian1108

SOURCE_MIRROR=registry.cn-beijing.aliyuncs.com/wny311
PUSH_MIRROR=172.20.58.10:5000/library
FILE=$1

for image in `cat $FILE` 
do docker pull $SOURCE_MIRROR/$image 
   docker tag $SOURCE_MIRROR/$image $PUSH_MIRROR/$image
   docker push $PUSH_MIRROR/$image
   docker rmi $PUSH_MIRROR/$image
   docker rmi $SOURCE_MIRROR/$image
done

