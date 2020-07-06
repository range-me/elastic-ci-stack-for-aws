#!/bin/bash
set -euxo pipefail

# Mount instance storage if we can
# https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/InstanceStorage.html

# Move docker root to the ephemeral device
if [[ "${BUILDKITE_ENABLE_INSTANCE_STORAGE:-false}" != "true" ]] ; then
  echo "Skipping mounting instance storage"
  exit 0
fi

# Install nvme-cli to list NVMe SSD instance store volumes
yum -y -d0 install nvme-cli

devicemount=/ephemeral
logicalname=/dev/md0
devices=($(nvme list | grep "Amazon EC2 NVMe Instance Storage"| cut -f1 -d' '))


if [[ "${#devices[@]}" -gt 0 ]] ; then
  mkdir -p "$devicemount"
fi

if [[ "${#devices[@]}" -eq 1 ]] ; then
  mkfs.xfs -f "${devices[0]}" > /dev/null
  mount -t xfs -o noatime "${devices[0]}" "$devicemount"

  if [ ! -f /etc/fstab.backup ]; then
    cp -rP /etc/fstab /etc/fstab.backup
    echo "${devices[0]} $devicemount    xfs  defaults  0 0" >> /etc/fstab
  fi

elif [[ "${#devices[@]}" -gt 1 ]] ; then
  mdadm \
    --create "$logicalname" \
    --level=0 \
    -c256 \
    --raid-devices="${#devices[@]}" "${devices[@]}"

  echo "DEVICE ${devices[*]}" > /etc/mdadm.conf

  mdadm --detail --scan >> /etc/mdadm.conf
  blockdev --setra 65536 "$logicalname"
  mkfs.xfs -f "$logicalname" > /dev/null
  mkdir -p "$devicemount"
  mount -t xfs -o noatime "$logicalname" "$devicemount"

  if [ ! -f /etc/fstab.backup ]; then
      cp -rP /etc/fstab /etc/fstab.backup
      echo "$logicalname $devicemount    xfs  defaults  0 0" >> /etc/fstab
  fi
fi
