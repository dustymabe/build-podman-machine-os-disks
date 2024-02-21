#!/usr/bin/bash
set -x -euo pipefail

# Run this script on a fully up to date Fedora 39 VM with SELinux
# in permissive mode and the following tools installed:
# sudo dnf install --enablerepo=updates-testing -y osbuild osbuild-tools osbuild-ostree jq
#
# Invocation of the script would look something like this:
#
# sudo ./build-podman-machine-os-disks.sh \
#   /path/to/podman-50-20240216.ociarchive qemu
#
# And it will create the output file in the current directory:
#   podman-50-20240216.ociarchive.x86_64.qemu.qcow2
#
# Another option is to specify no platform and it will create all of
# them that are configured:
#
# sudo ./build-podman-machine-os-disks.sh \
#   /path/to/podman-50-20240216.ociarchive
#
# And it will create the output file in the current directory:
#   podman-50-20240216.ociarchive.x86_64.applehv.raw
#   podman-50-20240216.ociarchive.x86_64.hyperv.vhdx
#   podman-50-20240216.ociarchive.x86_64.qemu.qcow2

ARCH=$(arch)
OCIARCHIVE=$1
PLATFORM="${2:-}" # Optional

check_rpm() {
    req=$1
    if ! rpm -q "$req" &>/dev/null; then
        echo "No $req. Can't continue" 1>&2
        return 1
    fi
}

check_rpms() {
    reqs=(osbuild osbuild-tools osbuild-ostree jq)
    for req in "${reqs[@]}"; do
        check_rpm "$req"
    done
}

main() {

    # Make sure RPMs are installed
    check_rpms
    # Make sure SELinux is permissive
    if [ "$(getenforce)" != "Permissive" ]; then
        echo "SELinux needs to be set to permissive mode"
        exit 1
    fi
    # Make sure we are effectively `root`
    if [ $UID -ne 0 ]; then
        echo "OSBuild needs to run with root permissions"
        exit 1
    fi
    # Make sure the given file exists
    if [ ! -f $OCIARCHIVE ]; then
        echo "need to pass in full path to .ociarchive file"
        exit 1
    fi

    gitrepotld="https://raw.githubusercontent.com/coreos/coreos-assembler/main/"
    curl -LO --fail "${gitrepotld}/src/runvm-osbuild"
    chmod +x runvm-osbuild
    for manifest in "coreos.osbuild.${ARCH}.mpp.yaml" platform.{applehv,hyperv,qemu,gcp}.ipp.yaml; do
        curl -LO --fail "${gitrepotld}/src/osbuild-manifests/${manifest}"
    done

    if [ "${PLATFORM:-}" == "" ]; then
        platforms=(applehv hyperv qemu)
    else
        platforms=($PLATFORM)
    fi

    for platform in "${platforms[@]}"; do

        suffix=
        case $platform in 
            applehv)
                suffix=raw
                ;;
            hyperv)
                suffix=vhdx
                ;;
            qemu)
                suffix=qcow2
                ;;
            *)
                echo "unknown platform provided"
                exit 1
                ;;
        esac
        outfile="./$(basename $OCIARCHIVE).${ARCH}.${platform}.${suffix}"

        cat > diskvars.json << EOF
{
	"osname": "fedora-coreos",
	"deploy-via-container": "true",
	"ostree-container": "${OCIARCHIVE}",
	"image-type": "${platform}",
	"container-imgref": "ostree-remote-registry:fedora:quay.io/containers/podman-machine-os:5.0",
	"metal-image-size": "3072",
	"cloud-image-size": "10240"
}
EOF
        ./runvm-osbuild                \
            --config diskvars.json     \
            --filepath "./${outfile}"  \
            --mpp "./coreos.osbuild.${ARCH}.mpp.yaml"
    done

}

main "$@"
