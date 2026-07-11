{ pkgs, ... }:

{
  systemd.user.services.nix-disk-cleanup = {
    Unit.Description = "Prune inactive Nix generations";

    Service = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "nix-disk-cleanup" ''
        set -euo pipefail
        ${pkgs.home-manager}/bin/home-manager expire-generations "-30 days"
        ${pkgs.nix}/bin/nix profile wipe-history --older-than 30d
        ${pkgs.nix}/bin/nix store gc
      '';
    };
  };

  systemd.user.timers.nix-disk-cleanup = {
    Unit.Description = "Run monthly Nix disk cleanup";

    Timer = {
      OnCalendar = "monthly";
      Persistent = true;
    };

    Install.WantedBy = [ "timers.target" ];
  };
}
