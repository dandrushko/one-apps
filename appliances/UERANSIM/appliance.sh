# ---------------------------------------------------------------------------- #
# Copyright 2024, OpenNebula Project, OpenNebula Systems                       #
#                                                                              #
# Licensed under the Apache License, Version 2.0 (the "License"); you may      #
# not use this file except in compliance with the License. You may obtain      #
# a copy of the License at                                                     #
#                                                                              #
# http://www.apache.org/licenses/LICENSE-2.0                                   #
#                                                                              #
# Unless required by applicable law or agreed to in writing, software          #
# distributed under the License is distributed on an "AS IS" BASIS,            #
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.     #
# See the License for the specific language governing permissions and          #
# limitations under the License.                                               #
# ---------------------------------------------------------------------------- #

# UERANSIM Appliance for for OpenNebula Marketplace

# ------------------------------------------------------------------------------
# List of contextualization parameters
# ------------------------------------------------------------------------------
ONE_SERVICE_PARAMS=(
    'ONEAPP_NETWORK_MCC' 'configure' 'Mobile Country Code value' 'O|text'
    'ONEAPP_NETWORK_MNC' 'configure' 'Mobile Network Code value (2 or 3 digits)' 'O|text'
    'ONEAPP_CELL_ID' 'configure' 'NR Cell Identity (36-bit)' 'O|text'
    'ONEAPP_GNB_ID' 'configure' 'NR gNB ID length in bits [22...32]' 'O|text'
    'ONEAPP_TAC_ID' 'configure' 'Tracking Area Code' 'O|text'
    'ONEAPP_AMF_IP' 'configure' 'AMF IP Address' 'O|text'
    'ONEAPP_AMF_PORT' 'configure' 'AMF_PORT' 'O|text'
    'ONEAPP_SST_ID' 'configure' 'List of supported S-NSSAIs by this gNB slices' 'O|text'
    'ONEAPP_UE_IMSI' 'configure' 'IMSI number of the UE. IMSI = [MCC|MNC|MSISDN] (In total 15 digits)' 'O|text'
    'ONEAPP_SUBSCRIPTOIN_KEY' 'configure' 'Permanent subscription key' 'O|text'
    'ONEAPP_OPERATOR_CODE' 'configure' 'Operator code (OP or OPC) of the UE' 'O|text'

)

# ------------------------------------------------------------------------------
# Appliance metadata
# ------------------------------------------------------------------------------

# Appliance metadata
ONE_SERVICE_NAME='UERANSIM - KVM'
ONE_SERVICE_VERSION='1.0.0'   #latest
ONE_SERVICE_BUILD=$(date +%s)
ONE_SERVICE_SHORT_DESCRIPTION='Appliance with UERANSIM 5G simulator'
ONE_SERVICE_DESCRIPTION=$(cat <<EOF
Appliance with preinstalled EURANSIM simulator.

After deploying the appliance, check the status of the deployment in
/etc/one-appliance/status. You chan check the appliance logs in
/var/log/one-appliance/.

**WARNING: The appliance does not permit recontextualization. Modifying the
context variables will not have any real efects on the running instance.**
EOF
)

# ------------------------------------------------------------------------------
# Contextualization defaults for appliance
# ------------------------------------------------------------------------------
NETWORK_MCC="${ONEAPP_NETWORK_MCC:-922}"
NETWORK_MNC="${ONEAPP_NETWORK_MNC:-77}"
CELL_ID="${ONEAPP_CELL_ID:-0x000000010}"
GNB_ID_LENGTH="${ONEAPP_GNB_ID_LENGTH:-32}"
TAC_ID="${ONEAPP_TAC_ID:-1}"
AMF_IP="${ONEAPP_AMF_IP:-127.0.0.1}"
AMF_PORT="${ONEAPP_AMF_PORT:-38412}"
SST_ID="${ONEAPP_SST_ID:-1}"

UE_IMSI="${ONEAPP_UE_IMSI:-imsi-999700000000001}"
SUBSCRIPTOIN_KEY="${ONEAPP_SUBSCRIPTOIN_KEY:-465B5CE8B199B49FAA5F0A2EE238A6BC}"
OPERATOR_CODE="${ONEAPP_OPERATOR_CODE:-E8ED289DEBA952E4283B54E88E6183CA}"

#
# ------------------------------------------------------------------------------
# Installation Stage => Installs requirements, downloads and unpacks Harbor
# ------------------------------------------------------------------------------
service_install() {
    msg info "Checking internet access..."
    check_internet_access
    install_requirements
    build_ueransim
    create_one_service_metadata
    msg info "Installation phase finished"
}

# ------------------------------------------------------------------------------
# Configuration Stage => Senerates gNodeB and UE config files
# ------------------------------------------------------------------------------
service_configure() {
    msg info "Starting configuration..."
   
    config_gnb
    config_ue

    msg info "Configuration phase finished"
}

# Will start gNB and UE 
service_bootstrap() {
    msg info "Starting bootstrap..."
    # Starting gNB process
     /opt/UERANSIM/build/nr-gnb -c  /opt/UERANSIM/config/ueransim-gnb.yaml > /var/log/gnb.log &
    if [ $? -ne 0 ]; then
        msg error "Error starting gNodeB, aborting..."
        exit 1
    else
        msg info "gNodeB was strarted..."
    fi
    sleep 5
    # Starting UE
    /opt/UERANSIM/build/nr-ue -c /opt/UERANSIM/config/ueransim-ue.yaml > /var/log/ue.log &
    if [ $? -ne 0 ]; then
        msg error "Error starting UE, aborting..."
        exit 1
    else
        msg info "UE was strarted..."
    fi

    msg info "Bootstrap phase finished"
}

# ------------------------------------------------------------------------------
# ------------------------------------------------------------------------------
# Function Definitions
# ------------------------------------------------------------------------------
# ------------------------------------------------------------------------------
check_internet_access() {
    # Ping Google's public DNS server
    if ping -c 1 8.8.8.8 &> /dev/null; then
        msg info "Internet access OK"
        return 0
    else
        msg error "The VM does not have internet access. Aborting UERANSIM deployment..."
        exit 1
    fi
}

install_requirements(){
    DEBIAN_FRONTEND=noninteractive
    apt-get update && apt install -y curl make gcc g++ libsctp-dev lksctp-tools snapd
    sudo snap install cmake --classic

}

build_ueransim(){
    cd /opt
    # Will clone repo only is it missing
    [ ! -d /opt/UERANSIM ] && git clone https://github.com/aligungr/UERANSIM
 
    # Will start build process only if gNB binary is mising
    cd UERANSIM
    if [ ! -f /opt/UERANSIM/build/nr-gnb ]; then
        make
    fi

    # If build wasn't successfull, report error and exit
    if [ $? -ne 0 ]; then
       msg error "Error building UERANSIM"
       exit 1
    fi

}

config_gnb(){
   # Assuming config/open5gs-gnb.yaml as the default UE config file
   cat << EOF > /opt/UERANSIM/config/ueransim-gnb.yaml
mcc: '${NETWORK_MCC}'
mnc: '${NETWORK_MNC}' 

nci: '${CELL_ID}'
idLength: ${GNB_ID_LENGTH}
tac: ${TAC_ID}

linkIp: 127.0.0.1   # gNB's local IP address for Radio Link Simulation (Usually same with local IP)
ngapIp: 127.0.0.1   # gNB's local IP address for N2 Interface (Usually same with local IP)
gtpIp: 127.0.0.1    # gNB's local IP address for N3 Interface (Usually same with local IP)

amfConfigs:
  - address: ${AMF_IP}
    port: ${AMF_PORT}

slices:
  - sst: ${SST_ID}

ignoreStreamIds: true

EOF
}

config_ue(){
   cat << EOF > /opt/UERANSIM/config/ueransim-ue.yaml
supi: '${UE_IMSI}'
mcc: '${NETWORK_MCC}'
mnc: '${NETWORK_MNC}'

key: '${SUBSCRIPTOIN_KEY}'
op: '${OPERATOR_CODE}'

opType: 'OPC'
amf: '8000'

gnbSearchList:
  - 127.0.0.1 

uacAic:
  mps: false
  mcs: false

uacAcc:
  normalClass: 0
  class11: false
  class12: false
  class13: false
  class14: false
  class15: false

sessions:
  - apn: internet
    emergency: false
    slice:
      sd: "0x111111"
      sst: 1
    type: IPv4

configured-nssai:
  - sst: 1
    sd: 0x111111

default-nssai:
  - sst: 1
    sd: 0x111111

integrity:
  IA1: true
  IA2: true
  IA3: true

ciphering:
  EA1: true
  EA2: true
  EA3: true

integrityMaxRate:
  uplink: 'full'
  downlink: 'full'

EOF

}


