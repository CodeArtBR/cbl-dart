#!/usr/bin/env bash

set -e

# === Globals =================================================================

if [[ -z "${ANDROID_HOME}" ]]; then
    case "$(uname)" in
    Darwin)
        ANDROID_HOME="~/Library/Android/sdk"
        ;;
    Linux)
        ANDROID_HOME="~/Android/Sdk"
        ;;
    *)
        echo "The environment variable ANDROID_HOME needs to be set"
        exit 1
        ;;
    esac
fi

emulatorName="cbl-dart"
emulatorPort=5554
serialName="emulator-$emulatorPort"
appBundleId="com.terwesten.gabriel.cbl_e2e_tests_flutter"

# === Usage ===================================================================

function usage() {
    cat <<-EOF
COMMANDS
    createAndStart -a API-LEVEL -d DEVICE
        creates and starts an emulator

    setupReversePort PORT
        proxies a port from the emulator to the host

    bugreport -o OUTPUT-DIRECTORY
        creates a bugreport for the emulator

DESCRIPTION
    -a API-LEVEL
        Android API level of the emulator

    -d DEVICE
        devices definition to the emulator

    -o OUTPUT-DIRECTORY
        directory to store outputs in
EOF
}

function usageFailure {
    usage
    exit 1
}

function requireOption() {
    if [[ -z "$3" ]]; then
        echo "$2 ($1) is required and was not provided"
        echo
        usageFailure
    fi
}

# === Command implementations =================================================

function createAndStart() {
    local apiLevel=""
    local device=""

    while getopts "a:d:" optName; do
        case "$optName" in
        a)
            apiLevel="$OPTARG"
            ;;
        d)
            device="$OPTARG"
            ;;
        ?)
            usageFailure
            ;;
        esac
    done

    requireOption -a API-LEVEL "$apiLevel"
    requireOption -d DEVICE "$device"

    echo 'KERNEL=="kvm", GROUP="kvm", MODE="0666", OPTIONS+="static_node=kvm"' | sudo tee /etc/udev/rules.d/99-kvm4all.rules
    sudo udevadm control --reload-rules
    sudo udevadm trigger --name-match=kvm

    sudo apt-get install libpulse0

    yes | "$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" --licenses

    # Install emulator.
    echo "Installing emulator..."
    "$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" emulator

    # Install system image.
    systemImage="system-images;android-$apiLevel;default;x86_64"
    echo "Installing system image '$systemImage' ..."
    "$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" "$systemImage"

    # Install platform tools.
    echo "Installing platform tools..."
    "$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" platform-tools

    # Create emulator.
    echo "Creating emulator..."
    "$ANDROID_HOME/cmdline-tools/latest/bin/avdmanager" create avd \
        --name "$emulatorName" \
        --package "$systemImage" \
        --device "$device"

    # Start emulator.
    echo "Staring emulator..."
    "$ANDROID_HOME/emulator/emulator" \
        -avd "$emulatorName" \
        -port "$emulatorPort" \
        -no-window \
        -no-audio \
        -no-boot-anim \
        -partition-size 4096 \
        >./emulator-logs.txt 2>&1 &

    sleep 10
    cat ./emulator-logs.txt

    # Wait for emulator to become ready.
    echo "Waiting for emulator to become ready..."
    "$ANDROID_HOME/platform-tools/adb" -s "$serialName" wait-for-device
    echo "Emulator is ready"
}

function setupReversePort() {
    local port="$1"

    requireOption -p PORT "$port"

    echo "Setting up reverse socket connect for port $port"
    "$ANDROID_HOME/platform-tools/adb" -s "$serialName" reverse "tcp:$1" "tcp:$1"
}

function bugreport() {
    local outputDirectory=""

    while getopts "o:" optName; do
        case "$optName" in
        o)
            outputDirectory="$OPTARG"
            ;;
        ?)
            usageFailure
            ;;
        esac
    done

    requireOption -o OUTPUT-DIRECTORY "$outputDirectory"

    echo "Creating bugreport..."

    mkdir -p "$outputDirectory"

    "$ANDROID_HOME/platform-tools/adb" \
        -s "$serialName" \
        bugreport \
        >"$outputDirectory/bugreport"

    echo "Created bugreport"
}

function copyAppData() {
    "$ANDROID_HOME/platform-tools/adb" shell "run-as $appBundleId cp -r /data/data/$appBundleId /mnt/sdcard"
    "$ANDROID_HOME/platform-tools/adb" pull "/mnt/sdcard/$appBundleId" "appData"
}

# === Parse command ===========================================================

if [[ $# -eq 0 ]]; then
    usageFailure
fi

commands=(
    createAndStart
    setupReversePort
    bugreport
    copyAppData
)

if [[ ! " ${commands[*]} " =~ " $1 " ]]; then
    echo "Unknown command $1"
    echo
    usageFailure
fi

"$@"
