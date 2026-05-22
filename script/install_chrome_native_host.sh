#!/bin/zsh
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
source_host_script="$repo_root/Browser Extension/chrome/native-host/fast-native-download-manager-host.py"
source_manifest="$repo_root/Browser Extension/chrome/native-host/dev.codex.fast_native_download_manager.json"
host_install_dir="$HOME/.fastndm"
host_script="$host_install_dir/chrome-native-host.py"
target_dir="$HOME/Library/Application Support/Google/Chrome/NativeMessagingHosts"
target_manifest="$target_dir/dev.codex.fast_native_download_manager.json"

mkdir -p "$host_install_dir"
cp "$source_host_script" "$host_script"
chmod +x "$host_script"
xattr -d com.apple.quarantine "$host_script" 2>/dev/null || true
xattr -d com.apple.provenance "$host_script" 2>/dev/null || true
mkdir -p "$target_dir"
sed "s#__HOST_PATH__#$host_script#g" "$source_manifest" > "$target_manifest"

echo "Installed Chrome native messaging host:"
echo "$target_manifest"
echo "Host executable:"
echo "$host_script"
