{ pkgs, ... }:

{
  home.packages = [
    (pkgs.writeShellApplication {
      name = "install-spark-desktop-apps";
      runtimeInputs = with pkgs; [
        coreutils
        curl
      ];
      text = ''
        if [ "$(uname -m)" != "aarch64" ] || [ ! -x /usr/bin/apt-get ]; then
          echo "This installer requires ARM64 Ubuntu or Debian." >&2
          exit 1
        fi

        download_dir="$(mktemp -d)"
        trap 'rm -rf "$download_dir"' EXIT

        curl --fail --location --retry 3 \
          --output "$download_dir/google-chrome-stable_current_arm64.deb" \
          https://dl.google.com/linux/direct/google-chrome-stable_current_arm64.deb
        curl --fail --location --retry 3 \
          --output "$download_dir/chatgpt_arm64.deb" \
          https://persistent.oaistatic.com/codex-app-prod/linux/deb/latest/chatgpt_arm64.deb

        /usr/bin/sudo /usr/bin/apt-get update
        /usr/bin/sudo /usr/bin/apt-get install -y \
          "$download_dir/google-chrome-stable_current_arm64.deb" \
          "$download_dir/chatgpt_arm64.deb"
      '';
    })
  ];
}
