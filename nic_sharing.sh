#!/bin/bash

# Check arguments for on/off action
if [[ "$#" -lt 3 || ("$1" != "on" && "$1" != "off") ]]; then
    echo "Usage: $0 <on|off> <source_interface> <destination_interface> [--ssid <SSID> --pass <PASSWORD> --dns <DNS_SERVER>]"
    exit 1
fi

# Variables
ACTION="$1"
INTERNET_INTERFACE="$2"
WIFI_INTERFACE="$3"
DNS_OPTION=false  # DNS configuration option
SSID=""
PASSWORD=""
AD_DNS_SERVER=""  # Default DNS server

# Parse optional arguments only if action is "on"
if [[ "$ACTION" == "on" ]]; then
    shift 3
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --ssid)
                SSID="$2"
                shift 2
                ;;
            --pass)
                PASSWORD="$2"
                shift 2
                ;;
            --dns)
                DNS_OPTION=true
                AD_DNS_SERVER="$2"
                shift 2
                ;;
            *)
                echo "Unknown option: $1"
                exit 1
                ;;
        esac
    done

    # Check if SSID and PASSWORD are provided when enabling sharing
    if [[ -z "$SSID" || -z "$PASSWORD" ]]; then
        echo "Error: --ssid and --pass are required when enabling sharing."
        exit 1
    fi
fi

DNSMASQ_CONF="/etc/dnsmasq.conf"
BACKUP_CONF="/etc/dnsmasq.conf.bak"
HOSTAPD_CONF="/etc/hostapd/hostapd.conf"
DHCP_RANGE="192.168.60.10,192.168.60.50,12h"
IP_ADDRESS="192.168.60.1"  # Gateway IP for Wi-Fi interface

# Function to generate hostapd.conf
generate_hostapd_conf() {
    echo "Creating hostapd configuration for SSID '$SSID'..."
    sudo tee "$HOSTAPD_CONF" > /dev/null <<EOL
interface=$WIFI_INTERFACE
driver=nl80211
ssid=$SSID
hw_mode=g
channel=6
macaddr_acl=0
auth_algs=1
ignore_broadcast_ssid=0
wpa=2
wpa_passphrase=$PASSWORD
wpa_key_mgmt=WPA-PSK
rsn_pairwise=CCMP
EOL
    echo "hostapd configuration created with SSID '$SSID'."
}

# Function to remove hostapd.conf
remove_hostapd_conf() {
    if [ -f "$HOSTAPD_CONF" ]; then
        sudo rm "$HOSTAPD_CONF"
        echo "hostapd configuration removed."
    fi
}

# Function to unblock Wi-Fi if blocked
unblock_wifi() {
    if rfkill list wifi | grep -q "Soft blocked: yes"; then
        sudo rfkill unblock wifi
        echo "Wi-Fi interface $WIFI_INTERFACE unblocked."
    fi
}

# Function to backup and configure dnsmasq.conf
setup_dnsmasq() {
    echo "Configuring dnsmasq for DHCP..."
    if [ ! -f "$BACKUP_CONF" ]; then
        sudo cp "$DNSMASQ_CONF" "$BACKUP_CONF"
        echo "Backup of dnsmasq.conf created."
    fi
    echo -e "\n# Temporary configuration for connection sharing" | sudo tee -a "$DNSMASQ_CONF" > /dev/null
    echo "interface=$WIFI_INTERFACE" | sudo tee -a "$DNSMASQ_CONF" > /dev/null
    echo "dhcp-range=$DHCP_RANGE" | sudo tee -a "$DNSMASQ_CONF" > /dev/null
    echo "dhcp-option=3,$IP_ADDRESS" | sudo tee -a "$DNSMASQ_CONF" > /dev/null

    if [ "$DNS_OPTION" = true ]; then
        echo "dhcp-option=6,$AD_DNS_SERVER" | sudo tee -a "$DNSMASQ_CONF" > /dev/null
        echo "dnsmasq configured with DNS server $AD_DNS_SERVER for all clients."
    fi
}

# Function to restore dnsmasq.conf
restore_dnsmasq() {
    echo "Restoring original dnsmasq configuration..."
    if [ -f "$BACKUP_CONF" ]; then
        sudo mv "$BACKUP_CONF" "$DNSMASQ_CONF"
        echo "dnsmasq.conf restored."
    fi
}

# Function to enable sharing and access point
enable_sharing() {
    echo "Activating Internet sharing from $INTERNET_INTERFACE to $WIFI_INTERFACE..."
    sudo sysctl -w net.ipv4.ip_forward=1
    echo "IP forwarding enabled."

    # Unblock Wi-Fi interface if necessary
    unblock_wifi

    # Remove any existing generic MASQUERADE rules
    sudo iptables -t nat -D POSTROUTING -o "$INTERNET_INTERFACE" -j MASQUERADE 2>/dev/null
    sudo iptables -t nat -D POSTROUTING -j MASQUERADE 2>/dev/null

    # Add specific MASQUERADE rule if it doesn't already exist
    if ! sudo iptables -t nat -C POSTROUTING -o "$INTERNET_INTERFACE" -j MASQUERADE 2>/dev/null; then
        sudo iptables -t nat -A POSTROUTING -o "$INTERNET_INTERFACE" -j MASQUERADE
        echo "NAT MASQUERADE rule added for $INTERNET_INTERFACE."
    else
        echo "NAT MASQUERADE rule for $INTERNET_INTERFACE already exists."
    fi

    # Add FORWARD rules if they do not already exist
    if ! sudo iptables -C FORWARD -i "$INTERNET_INTERFACE" -o "$WIFI_INTERFACE" -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null; then
        sudo iptables -A FORWARD -i "$INTERNET_INTERFACE" -o "$WIFI_INTERFACE" -m state --state RELATED,ESTABLISHED -j ACCEPT
        echo "FORWARD rule for RELATED,ESTABLISHED added."
    fi

    if ! sudo iptables -C FORWARD -i "$WIFI_INTERFACE" -o "$INTERNET_INTERFACE" -j ACCEPT 2>/dev/null; then
        sudo iptables -A FORWARD -i "$WIFI_INTERFACE" -o "$INTERNET_INTERFACE" -j ACCEPT
        echo "FORWARD rule for outgoing traffic added."
    fi

    # Configure the Wi-Fi interface
    sudo ip addr add "$IP_ADDRESS/24" dev "$WIFI_INTERFACE"
    sudo ip link set "$WIFI_INTERFACE" up
    echo "Wi-Fi interface $WIFI_INTERFACE configured with IP $IP_ADDRESS."

    # Configure dnsmasq and hostapd
    setup_dnsmasq
    sudo systemctl restart dnsmasq
    echo "dnsmasq restarted."
    generate_hostapd_conf
    sudo hostapd "$HOSTAPD_CONF" -B
    echo "hostapd started with SSID '$SSID'."
    echo "Internet sharing enabled."
}

# Function to disable sharing and access point
disable_sharing() {
    echo "Deactivating Internet sharing..."
    sudo sysctl -w net.ipv4.ip_forward=0
    echo "IP forwarding disabled."

    # Remove MASQUERADE rule for the specific interface
    if sudo iptables -t nat -C POSTROUTING -o "$INTERNET_INTERFACE" -j MASQUERADE 2>/dev/null; then
        sudo iptables -t nat -D POSTROUTING -o "$INTERNET_INTERFACE" -j MASQUERADE
        echo "NAT MASQUERADE rule removed for $INTERNET_INTERFACE."
    fi

    # Remove FORWARD rules if they exist
    if sudo iptables -C FORWARD -i "$INTERNET_INTERFACE" -o "$WIFI_INTERFACE" -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null; then
        sudo iptables -D FORWARD -i "$INTERNET_INTERFACE" -o "$WIFI_INTERFACE" -m state --state RELATED,ESTABLISHED -j ACCEPT
        echo "FORWARD rule for RELATED,ESTABLISHED removed."
    fi

    if sudo iptables -C FORWARD -i "$WIFI_INTERFACE" -o "$INTERNET_INTERFACE" -j ACCEPT 2>/dev/null; then
        sudo iptables -D FORWARD -i "$WIFI_INTERFACE" -o "$INTERNET_INTERFACE" -j ACCEPT
        echo "FORWARD rule for outgoing traffic removed."
    fi

    # Disable Wi-Fi interface
    sudo ip addr flush dev "$WIFI_INTERFACE"
    sudo ip link set "$WIFI_INTERFACE" down
    echo "Wi-Fi interface $WIFI_INTERFACE down."

    # Stop hostapd and remove hostapd configuration
    sudo pkill hostapd
    remove_hostapd_conf
    echo "hostapd stopped and configuration removed."

    # Restore dnsmasq configuration
    restore_dnsmasq
    sudo systemctl restart dnsmasq
    echo "dnsmasq restarted."
    echo "Internet sharing disabled."
}

# Enable or disable sharing based on the action argument
if [ "$ACTION" == "on" ]; then
    enable_sharing
elif [ "$ACTION" == "off" ]; then
    disable_sharing
fi
