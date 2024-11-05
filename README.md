# Internet Sharing Script

This script enables internet sharing from one network interface (e.g., connected to the internet or VPN) to another (e.g., a Wi-Fi access point). It dynamically configures IP forwarding, sets up iptables rules for NAT, configures `dnsmasq` for DHCP services, and generates an `hostapd` configuration file to create a Wi-Fi access point. The script also allows optional configuration for a DNS server and automatically unblocks the Wi-Fi interface if it is blocked.

## Requirements

- `dnsmasq`: Used to provide DHCP services.
- `hostapd`: Used to create a Wi-Fi access point.
- `iptables`: For configuring NAT (Network Address Translation) rules.
- `rfkill`: Used to unblock the Wi-Fi interface if needed.

## Installation

Ensure `dnsmasq`, `hostapd`, and `rfkill` are installed on your system:
```bash
sudo apt update
sudo apt install dnsmasq hostapd rfkill
```

## Usage

```bash
./nic_sharing.sh <on|off> <source_interface> <destination_interface> --ssid <SSID> --pass <PASSWORD> [--dns <DNS_SERVER>]
```

- `<on|off>`: Enables or disables internet sharing.
- `<source_interface>`: Network interface connected to the internet or VPN (e.g., `eth0` or `wg0` or `tun0` ...).
- `<destination_interface>`: Network interface to act as the access point (e.g., `wlan0`).
- `--ssid <SSID>`: The SSID name for the Wi-Fi access point.
- `--pass <PASSWORD>`: The password for the Wi-Fi access point.
- `--dns <DNS_SERVER>`: Optional. Sets a custom DNS server (e.g., for an Active Directory DNS) for clients connecting to the Wi-Fi access point.

### Example Commands

#### Enabling Internet Sharing

To enable internet sharing from the source interface `eth0` to Wi-Fi interface `wlan0` with a custom SSID, password, and DNS server:
```bash
./nic_sharing.sh on eth0 wlan0 --ssid "MyAccessPoint" --pass "MySecurePassword" --dns 192.168.x.x
```

#### Disabling Internet Sharing

To disable internet sharing and revert configurations:
```bash
./nic_sharing.sh off eth0 wlan0
```

## Features

- **Automatic DHCP and Gateway Configuration**: Configures `dnsmasq` to provide DHCP services on the specified Wi-Fi interface with a predefined IP range.
- **Custom DNS Option**: Allows specifying a custom DNS server with the `--dns` option, such as a DNS server in an Active Directory environment.
- **Dynamic Wi-Fi Configuration**: Generates a temporary `hostapd.conf` file based on specified SSID and password. This file is deleted upon deactivation.
- **Wi-Fi Interface Unblocking**: Checks if the Wi-Fi interface is blocked and unblocks it if necessary.
- **Reverts to Original State**: When disabled, all configurations, including IP forwarding, iptables rules, and DHCP settings, are restored to their original state.

## How It Works

1. **Enabling Sharing (`on`)**:
   - Enables IP forwarding.
   - Configures NAT for internet sharing through iptables.
   - Configures `dnsmasq` to provide DHCP and (optionally) a custom DNS server.
   - Generates an `hostapd.conf` file with the specified SSID and password, and starts `hostapd` to create a Wi-Fi access point.

2. **Disabling Sharing (`off`)**:
   - Disables IP forwarding.
   - Removes NAT and iptables rules.
   - Restores the original `dnsmasq` configuration.
   - Stops `hostapd` and deletes the generated `hostapd.conf` file.

### Important Notes

- If the Wi-Fi interface is blocked by `rfkill`, the script will automatically unblock it.
- The script automatically backs up the original `dnsmasq.conf` and restores it when disabled, ensuring the system returns to its prior state.
- Ensure to run the script with `sudo` to apply system-wide network configurations.

### Example Output

When enabling sharing:
```plaintext
Activating Internet sharing from eth0 to wlan0...
IP forwarding enabled.
NAT MASQUERADE rule added for eth0.
FORWARD rule for RELATED,ESTABLISHED added.
FORWARD rule for outgoing traffic added.
Wi-Fi interface wlp0s20f3 configured with IP 192.168.60.1.
Creating hostapd configuration for SSID 'MyAccessPoint'...
hostapd configuration created with SSID 'MyAccessPoint'.
hostapd started with SSID 'MyAccessPoint'.
dnsmasq restarted.
Internet sharing enabled.
```

When disabling sharing:
```plaintext
Deactivating Internet sharing...
IP forwarding disabled.
NAT MASQUERADE rule removed for eth0.
FORWARD rule for RELATED,ESTABLISHED removed.
FORWARD rule for outgoing traffic removed.
Wi-Fi interface wlan0 down.
hostapd stopped and configuration removed.
dnsmasq restarted.
Internet sharing disabled.
```

## Troubleshooting

If the Wi-Fi access point is not visible or cannot connect to the internet:
- Ensure the Wi-Fi adapter supports AP mode and is not blocked by hardware or software.
- Confirm that `hostapd`, `dnsmasq`, and `iptables` are installed and configured correctly.
- Check `hostapd` and `dnsmasq` logs for any errors with:
  ```bash
  sudo journalctl -u hostapd
  sudo journalctl -u dnsmasq
  ```

## License

This project is licensed under the MIT License.

