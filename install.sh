#!/usr/bin/env bash

set -e

SERVICE_NAME="mqtt-clip"
INSTALL_DIR="$HOME/.local/lib/$SERVICE_NAME"
BIN_DIR="$HOME/.local/bin"
CONFIG_DIR="$HOME/.config/$SERVICE_NAME"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT_PATH="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"

detect_os() {
    case "$(uname -s)" in
        Linux*)     OS="linux";;
        Darwin*)    OS="macos";;
        *)          echo "Error: Unsupported OS"; exit 1;;
    esac
}

check_dependencies() {
    if ! command -v dotnet &> /dev/null; then
        echo "Error: .NET SDK not found. Please install .NET 9 SDK."
        exit 1
    fi

    local version
    version=$(dotnet --version | cut -d. -f1)
    if [ "$version" -lt 9 ]; then
        echo "Error: .NET 9 SDK required. Found version $(dotnet --version)"
        exit 1
    fi
}

get_rid() {
    case "$OS" in
        linux)     echo "linux-x64";;
        macos)
            case "$(uname -m)" in
                arm64)    echo "osx-arm64";;
                x86_64)   echo "osx-x64";;
            esac
            ;;
    esac
}

build() {
    echo "Building $SERVICE_NAME..."

    local rid
    rid=$(get_rid)

    dotnet publish -c Release -r "$rid" --self-contained true -o "$INSTALL_DIR" -p:PublishSingleFile=false

    if [ -f "$INSTALL_DIR/Mqtt.Clipboard" ]; then
        mv "$INSTALL_DIR/Mqtt.Clipboard" "$INSTALL_DIR/mqtt-clip"
    fi

    echo "Build complete."
}

create_config() {
    mkdir -p "$CONFIG_DIR"

    local config_file="$CONFIG_DIR/appsettings.json"

    if [ ! -f "$config_file" ]; then
        cp "$SCRIPT_DIR/appsettings.json" "$CONFIG_DIR"
        echo "Config written to $config_file"
    fi
}

create_service_linux() {
    mkdir -p "$HOME/.config/systemd/user"

    cat > "$HOME/.config/systemd/user/mqtt-clip.service" << EOF
[Unit]
Description=mqtt-clip MQTT Listener
After=network.target

[Service]
Type=simple
WorkingDirectory=$CONFIG_DIR
ExecStart=$BIN_DIR/mqtt-clip --config $CONFIG_DIR/appsettings.json
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
EOF

    echo "Created systemd service: $HOME/.config/systemd/user/mqtt-clip.service"
}

create_service_macos() {
    mkdir -p "$HOME/Library/LaunchAgents"

    cat > "$HOME/Library/LaunchAgents/com.mqttclip.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.mqttclip</string>
    <key>ProgramArguments</key>
    <array>
        <string>$BIN_DIR/mqtt-clip</string>
        <string>--config</string>
        <string>$CONFIG_DIR/appsettings.json</string>
    </array>
    <key>WorkingDirectory</key>
    <string>$CONFIG_DIR</string>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>$HOME/.local/share/mqtt-clip.log</string>
    <key>StandardErrorPath</key>
    <string>$HOME/.local/share/mqtt-clip.log</string>
</dict>
</plist>
EOF

    echo "Created launchd plist: $HOME/Library/LaunchAgents/com.mqttclip.plist"
}

install_service() {
    echo "Installing service..."

    if [ "$OS" = "linux" ]; then
        create_service_linux
        systemctl --user daemon-reload
        if systemctl list-units --type=service --user | grep -q clip; then
            restart_service
        else
            systemctl --user enable --now mqtt-clip
        fi
    else
        create_service_macos
        launchctl load "$HOME/Library/LaunchAgents/com.mqttclip.plist"
        restart_service
    fi

    echo "Service installed and started."
}

copy_self() {
    cp "$SCRIPT_PATH" "$INSTALL_DIR/mqtt-clipctl"
    chmod +x "$INSTALL_DIR/mqtt-clipctl"

    cat > "$BIN_DIR/mqtt-clip" << 'WRAPPER'
#!/usr/bin/env bash

COMMAND="$1"

case "$COMMAND" in
    start|stop|restart|status|uninstall|help|--help|-h)
        exec "$HOME/.local/lib/mqtt-clip/mqtt-clipctl" "$@"
        ;;
    *)
        # exec "$HOME/.local/lib/mqtt-clip/mqtt-clip" "$@"
        exec "$HOME/.local/lib/mqtt-clip/mqtt-clip" "--help"
        ;;
esac
WRAPPER
    chmod +x "$BIN_DIR/mqtt-clip"

    echo "Created CLI at $BIN_DIR/mqtt-clip"
}

check_path() {
    local bin_dir="$HOME/.local/bin"
    if [[ ":$PATH:" != *":$bin_dir:"* ]]; then
        echo ""
        echo "Warning: $bin_dir is not in your PATH."
        echo "Add this to your shell profile (.bashrc, .zshrc, etc):"
        echo "  export PATH=\"\$PATH:$bin_dir\""
    fi
}

start_service() {
    echo "Starting $SERVICE_NAME..."

    if [ "$OS" = "linux" ]; then
        systemctl --user start mqtt-clip
    else
        launchctl load "$HOME/Library/LaunchAgents/com.mqttclip.plist"
    fi
}

stop_service() {
    echo "Stopping $SERVICE_NAME..."

    if [ "$OS" = "linux" ]; then
        systemctl --user stop mqtt-clip 2>/dev/null || true
    else
        launchctl unload "$HOME/Library/LaunchAgents/com.mqttclip.plist" 2>/dev/null || true
    fi
}

restart_service() {
    stop_service
    sleep 1
    start_service
}

service_status() {
    if [ "$OS" = "linux" ]; then
        systemctl --user status mqtt-clip
    else
        tail "$HOME/.local/share/mqtt-clip.log"
        echo ""
        echo "[STATUS] $(launchctl list | grep mqttclip || echo "Service not running")"
    fi
}

uninstall() {
    echo "Uninstalling $SERVICE_NAME..."

    stop_service

    if [ "$OS" = "linux" ]; then
        systemctl --user disable mqtt-clip 2>/dev/null || true
        rm -f "$HOME/.config/systemd/user/mqtt-clip.service"
    else
        rm -f "$HOME/Library/LaunchAgents/com.mqttclip.plist"
    fi

    rm -rf "$INSTALL_DIR"
    rm -f "$BIN_DIR/mqtt-clip"
    rm -f "$HOME/.local/share/mqtt-clip.log"
    rm -rf "$CONFIG_DIR"

    echo "Uninstall complete."
}

show_help() {
    cat << EOF
Mqtt.Clipboard Install Script

Usage: mqtt-clip [command]

Commands:
    install       Build and install the service
    start         Start the service
    stop          Stop the service
    restart       Restart the service
    status        Show service status
    uninstall     Stop and remove the service

The service can be controlled via:
    Linux:  systemctl --user <command> mqtt-clip
    macOS:  launchctl <command> com.mqttclip

Config location: $CONFIG_DIR/appsettings.json
Edit this file and run 'mqtt-clip restart' to apply changes.
EOF
}

COMMAND="${1:-install}"
detect_os

case "$COMMAND" in
    install)
        check_dependencies
        build
        create_config
        copy_self
        install_service
        check_path
        echo ""
        echo "Installation complete!"
        echo "Binaries: $INSTALL_DIR"
        echo "CLI: $BIN_DIR/mqtt-clip"
        echo "Config: $CONFIG_DIR/appsettings.json"
        echo "Edit config and run 'mqtt-clip restart' to apply changes."
        ;;
    start)      start_service ;;
    stop)       stop_service ;;
    restart)    restart_service ;;
    status)     service_status ;;
    uninstall)  uninstall ;;
    help|--help|-h) show_help ;;
    *)          echo "Unknown command: $COMMAND"; show_help; exit 1 ;;
esac
