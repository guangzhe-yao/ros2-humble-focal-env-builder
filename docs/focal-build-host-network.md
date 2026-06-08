# Focal Build Host Network

The focal build host used for validation is:

```text
nav01@172.16.11.164
```

On 2026-06-08, the Wi-Fi connection was changed from DHCP to a manual address
while keeping the same IP that DHCP had assigned:

```text
Connection: ZJ-Humanoid
Interface:  wlp3s0
Address:    172.16.11.164/22
Netmask:    255.255.252.0
Gateway:    172.16.11.248
DNS:        152.104.168.178
```

After this change, these endpoints were reachable from the build host:

```text
https://raw.githubusercontent.com/ros/rosdistro/master/rosdep/base.yaml
https://github.com
```

The USTC rosdistro mirror was slower from this network at the time of testing,
so the host was restored to official GitHub rosdep sources.

## Commands Used

Create a DHCP backup profile:

```bash
sudo nmcli connection clone "ZJ-Humanoid" "ZJ-Humanoid-dhcp-backup"
sudo nmcli connection modify "ZJ-Humanoid-dhcp-backup" connection.autoconnect no
```

Set the Wi-Fi profile to manual IPv4:

```bash
sudo nmcli connection modify "ZJ-Humanoid" \
  ipv4.method manual \
  ipv4.addresses "172.16.11.164/22" \
  ipv4.gateway "172.16.11.248" \
  ipv4.dns "152.104.168.178" \
  ipv4.ignore-auto-dns yes

sudo systemctl restart NetworkManager
```

Restore official rosdep source URLs after GitHub access works:

```bash
sudo cp /etc/ros/rosdep/sources.list.d/20-default.list.before-mirror \
  /etc/ros/rosdep/sources.list.d/20-default.list
sudo sed -i '/^gbpdistro /d' /etc/ros/rosdep/sources.list.d/20-default.list
sudo rm -f /etc/ros/rosdep/rosdistro_index_url
rosdep update
```

## Current Validation

The active Wi-Fi profile was verified with:

```bash
nmcli -f connection.id,ipv4.method,ipv4.addresses,ipv4.gateway,ipv4.dns,ipv4.ignore-auto-dns connection show "ZJ-Humanoid"
ip route
```

Expected result:

```text
ipv4.method:          manual
ipv4.addresses:       172.16.11.164/22
ipv4.gateway:         172.16.11.248
ipv4.dns:             152.104.168.178
default via 172.16.11.248 dev wlp3s0 proto static
```

