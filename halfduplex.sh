#!/bin/bash
# Color Codes
Purple='\033[0;35m'
Cyan='\033[0;36m'
YELLOW='\033[0;33m'
White='\033[0;96m'
RED='\033[0;31m'
NC='\033[0m' # No Color

clear
echo "
══════════════════════════════════════════════════════════════════════════════════════
        ____ _ _
    , / ) /| / /
-------/____/---_--_----__---)__--_/_---/-| -/-----__--_/_-----------__---)__---/-__-
  / / / / ) / ) / ) / / | / /___) / | /| / / ) / ) /(
_/___/________/_/__/_(___(_/_____(_ __/___|/____(___ _(_ __|/_|/__(___/_/_____/___\__
══════════════════════════════════════════════════════════════════════════════════════"

# Generate random password (12 chars, alphanumeric + symbols)
generate_password() {
  cat /dev/urandom | tr -dc 'A-Za-z0-9!@#$%^&*()_+' | fold -w 12 | head -n 1
}

# Check AVX-512 support
has_avx512() {
  if grep -q " avx512" /proc/cpuinfo; then
    return 0
  else
    return 1
  fi
}

# Detect architecture and select best binary
ARCH=$(uname -m)
if [ "$ARCH" == "aarch64" ]; then
  ASSET_NAME="Waterwall-linux-gcc-arm64.zip"
  echo -e "${Cyan}ARM64 detected → Using gcc-arm64${NC}"
elif [ "$ARCH" == "x86_64" ]; then
  if has_avx512; then
    ASSET_NAME="Waterwall-linux-clang-avx512f-x64.zip"
    echo -e "${Cyan}x86_64 with AVX-512 → Using clang-avx512f${NC}"
  else
    ASSET_NAME="Waterwall-linux-clang-x64.zip"
    echo -e "${Cyan}x86_64 detected → Using clang-x64${NC}"
  fi
else
  echo -e "${RED}Unsupported architecture: $ARCH${NC}"
  exit 1
fi

# Download and unzip function
download_and_unzip() {
  local url="$1"
  local dest="$2"
  echo -e "${YELLOW}Downloading $dest...${NC}"
  wget -q --show-progress -O "$dest" "$url"
  if [ $? -ne 0 ]; then
    echo -e "${RED}Download failed.${NC}"
    return 1
  fi
  echo -e "${YELLOW}Unzipping...${NC}"
  unzip -o "$dest"
  if [ $? -ne 0 ] || [ ! -f "Waterwall" ]; then
    echo -e "${RED}Unzip failed or binary missing.${NC}"
    return 1
  fi
  chmod +x Waterwall
  rm -f "$dest"
  echo -e "${Cyan}Binary ready. Version: $(./Waterwall --version 2>/dev/null || echo 'unknown')${NC}"
}

# Get latest release URL
get_latest_release_url() {
  local api_url="https://api.github.com/repos/alirezasamavarchi/WaterWall/releases/latest"
  local response=$(curl -s "$api_url")
  if [ $? -ne 0 ] || [ -z "$response" ]; then return 1; fi
  local asset_url=$(echo "$response" | jq -r ".assets[] | select(.name == \"$ASSET_NAME\") | .browser_download_url")
  if [ -z "$asset_url" ] || [ "$asset_url" == "null" ]; then return 1; fi
  echo "$asset_url"
}

# Get specific version URL
get_specific_release_url() {
  local version=$1
  local api_url="https://api.github.com/repos/alirezasamavarchi/WaterWall/releases/tags/$version"
  local response=$(curl -s "$api_url")
  if [ $? -ne 0 ] || [ -z "$response" ]; then return 1; fi
  local asset_url=$(echo "$response" | jq -r ".assets[] | select(.name == \"$ASSET_NAME\") | .browser_download_url")
  if [ -z "$asset_url" ] || [ "$asset_url" == "null" ]; then return 1; fi
  echo "$asset_url"
}

setup_waterwall_service() {
  cat > /etc/systemd/system/waterwall.service << EOF
[Unit]
Description=Waterwall Service
After=network.target

[Service]
ExecStart=/root/RRT/Waterwall
WorkingDirectory=/root/RRT
Restart=always
RestartSec=5
User=root
StandardOutput=null
StandardError=null

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable waterwall
  systemctl start waterwall
  echo -e "${Cyan}Service created and started.${NC}"
}

while true; do
  echo -e "${Purple}Select option:${NC}"
  echo -e "${White}1. IRAN${NC}"
  echo -e "${Cyan}2. KHAREJ${NC}"
  echo -e "${White}3. Uninstall${NC}"
  echo -e "${Cyan}0. Exit${NC}"
  read -p "Choice: " choice

  if [[ "$choice" -eq 1 || "$choice" -eq 2 ]]; then
    # Fix SSH port if needed
    SSHD_CONFIG_FILE="/etc/ssh/sshd_config"
    if ! grep -qE '^Port 22' "$SSHD_CONFIG_FILE" && ! grep -qE '^#Port 22' "$SSHD_CONFIG_FILE"; then
      sudo sed -i -E 's/^(#Port |Port )[0-9]+/Port 22/' "$SSHD_CONFIG_FILE"
      echo "SSH port set to 22."
      sudo systemctl restart sshd || sudo service ssh restart
    fi

    mkdir -p /root/RRT
    cd /root/RRT
    apt update -y && apt install unzip jq wget -y

    # Password setup
    echo -e "${Purple}Reality Password:${NC}"
    read -p "Custom password (Enter for random): " custom_pass
    if [ -z "$custom_pass" ]; then
      REALITY_PASS=$(generate_password)
      echo -e "${YELLOW}Generated: ${RED}$REALITY_PASS${NC}"
    else
      REALITY_PASS="$custom_pass"
      echo -e "${Cyan}Using custom password.${NC}"
    fi

    # Tunnel port setup
    echo -e "${Purple}Main Tunnel Port (e.g. 2333):${NC}"
    read -p "Port (default 443): " input_port
    TUNNEL_PORT=${input_port:-443}
    echo -e "${Cyan}Tunnel port: $TUNNEL_PORT${NC}"
    if [ "$TUNNEL_PORT" != "443" ]; then
      echo -e "${YELLOW}Reminder: Open $TUNNEL_PORT/tcp in firewall on both servers.${NC}"
    fi

    # Users port range (only for Iran)
    if [ "$choice" -eq 1 ]; then
      echo -e "${Purple}Users Port Range (Iran side):${NC}"
      read -p "Start (default 10000): " range_start
      read -p "End (default 20000): " range_end
      RANGE_START=${range_start:-10000}
      RANGE_END=${range_end:-20000}
      echo -e "${Cyan}Client ports: $RANGE_START-$RANGE_END${NC}"
    fi

    # Install core
    read -p "Latest version? (y/n): " answer
    if [[ "$answer" =~ ^[Yy]$ ]]; then
      url=$(get_latest_release_url)
      if [ $? -ne 0 ] || [ -z "$url" ]; then
        fallback="Waterwall-linux-clang-x64.zip"
        url=$(curl -s "https://api.github.com/repos/alirezasamavarchi/WaterWall/releases/latest" | jq -r ".assets[] | select(.name == \"$fallback\") | .browser_download_url")
        if [ -z "$url" ] || [ "$url" == "null" ]; then
          echo -e "${RED}Failed to find asset.${NC}"
          exit 1
        fi
        echo -e "${YELLOW}Fallback to $fallback${NC}"
      fi
      download_and_unzip "$url" "$ASSET_NAME" || download_and_unzip "$url" "$fallback"
    else
      read -p "Version (e.g. v1.41): " version
      url=$(get_specific_release_url "$version")
      if [ $? -ne 0 ] || [ -z "$url" ]; then exit 1; fi
      download_and_unzip "$url" "$ASSET_NAME"
    fi

    # core.json
    cat > core.json << EOF
{
    "log": {
        "path": "log/",
        "core": { "loglevel": "INFO", "file": "core.log", "console": true },
        "network": { "loglevel": "INFO", "file": "network.log", "console": true },
        "dns": { "loglevel": "SILENT", "file": "dns.log", "console": false }
    },
    "dns": {},
    "misc": { "workers": 0, "ram-profile": "server", "libs-path": "libs/" },
    "configs": [ "config.json" ]
}
EOF
  fi

  if [ "$choice" -eq 1 ]; then
    public_ip=$(curl -s https://api.ipify.org || wget -qO- https://api.ipify.org)
    echo -e "${Cyan}Iran selected.${NC}"
    read -p "Kharej IPv4: " ip_remote
    read -p "SNI (default ipmart.shop): " input_sni
    HOSTNAME=${input_sni:-ipmart.shop}

    cat > config.json << EOF
{
    "name": "reverse_reality_grpc_hd_multiport_server",
    "nodes": [
        {
            "name": "users_inbound",
            "type": "TcpListener",
            "settings": { "address": "0.0.0.0", "port": [$RANGE_START,$RANGE_END], "nodelay": true },
            "next": "header"
        },
        { "name": "header", "type": "HeaderClient", "settings": { "data": "src_context->port" }, "next": "bridge2" },
        { "name": "bridge2", "type": "Bridge", "settings": { "pair": "bridge1" } },
        { "name": "bridge1", "type": "Bridge", "settings": { "pair": "bridge2" } },
        { "name": "reverse_server", "type": "ReverseServer", "settings": {}, "next": "bridge1" },
        { "name": "pbserver", "type": "ProtoBufServer", "settings": {}, "next": "reverse_server" },
        { "name": "h2server", "type": "Http2Server", "settings": {}, "next": "pbserver" },
        { "name": "halfs", "type": "HalfDuplexServer", "settings": {}, "next": "h2server" },
        {
            "name": "reality_server",
            "type": "RealityServer",
            "settings": { "destination": "reality_dest", "password": "$REALITY_PASS" },
            "next": "halfs"
        },
        {
            "name": "kharej_inbound",
            "type": "TcpListener",
            "settings": { "address": "0.0.0.0", "port": $TUNNEL_PORT, "nodelay": true, "whitelist": ["$ip_remote/32"] },
            "next": "reality_server"
        },
        {
            "name": "reality_dest",
            "type": "TcpConnector",
            "settings": { "nodelay": true, "address": "$HOSTNAME", "port": $TUNNEL_PORT }
        }
    ]
}
EOF
    sleep 0.5
    setup_waterwall_service
    sleep 0.5
    echo -e "${Cyan}Iran IP: $public_ip${NC}"
    echo -e "${Purple}Kharej IP: $ip_remote${NC}"
    echo -e "${Cyan}SNI: $HOSTNAME${NC}"
    echo ""
    echo -e "${RED}Important:${NC}"
    echo "Tunnel Port     : $TUNNEL_PORT"
    echo "Reality Password: $REALITY_PASS"
    echo "Client Ports    : $RANGE_START - $RANGE_END"
    echo -e "${YELLOW}Use same password & tunnel port on Kharej side.${NC}"
    read -p "Press Enter..." dummy

  elif [ "$choice" -eq 2 ]; then
    public_ip=$(curl -s https://api.ipify.org || wget -qO- https://api.ipify.org)
    echo -e "${Purple}Kharej selected.${NC}"
    read -p "Iran IPv4: " ip_remote
    read -p "SNI (default ipmart.shop): " input_sni
    HOSTNAME=${input_sni:-ipmart.shop}

    cat > config.json << EOF
{
    "name": "reverse_reality_grpc_client_hd_multiport_client",
    "nodes": [
        { "name": "outbound_to_core", "type": "TcpConnector", "settings": { "nodelay": true, "address": "127.0.0.1", "port": "dest_context->port" } },
        { "name": "header", "type": "HeaderServer", "settings": { "override": "dest_context->port" }, "next": "outbound_to_core" },
        { "name": "bridge1", "type": "Bridge", "settings": { "pair": "bridge2" }, "next": "header" },
        { "name": "bridge2", "type": "Bridge", "settings": { "pair": "bridge1" }, "next": "reverse_client" },
        { "name": "reverse_client", "type": "ReverseClient", "settings": { "minimum-unused": 16 }, "next": "pbclient" },
        { "name": "pbclient", "type": "ProtoBufClient", "settings": {}, "next": "h2client" },
        {
            "name": "h2client",
            "type": "Http2Client",
            "settings": { "host": "$HOSTNAME", "port": $TUNNEL_PORT, "path": "/", "contenttype": "application/grpc", "concurrency": 64 },
            "next": "halfc"
        },
        { "name": "halfc", "type": "HalfDuplexClient", "next": "reality_client" },
        {
            "name": "reality_client",
            "type": "RealityClient",
            "settings": { "sni": "$HOSTNAME", "password": "$REALITY_PASS" },
            "next": "outbound_to_iran"
        },
        {
            "name": "outbound_to_iran",
            "type": "TcpConnector",
            "settings": { "nodelay": true, "address": "$ip_remote", "port": $TUNNEL_PORT }
        }
    ]
}
EOF
    sleep 0.5
    setup_waterwall_service
    sleep 0.5
    echo -e "${Purple}Kharej IP: $public_ip${NC}"
    echo -e "${Cyan}Iran IP: $ip_remote${NC}"
    echo -e "${Purple}SNI: $HOSTNAME${NC}"
    echo ""
    echo -e "${RED}Important:${NC}"
    echo "Tunnel Port     : $TUNNEL_PORT"
    echo "Reality Password: $REALITY_PASS"
    echo -e "${YELLOW}Use same values on Iran side.${NC}"
    read -p "Press Enter..." dummy

  elif [ "$choice" -eq 3 ]; then
    sudo systemctl stop waterwall 2>/dev/null
    sudo systemctl disable waterwall 2>/dev/null
    rm -f /etc/systemd/system/waterwall.service
    pkill -f Waterwall 2>/dev/null
    rm -rf /root/RRT
    echo -e "${YELLOW}Uninstall done.${NC}"
    read -p "Press Enter..." dummy
  elif [ "$choice" -eq 0 ]; then
    echo "Exit."
    break
  else
    echo -e "${RED}Invalid.${NC}"
  fi
done
