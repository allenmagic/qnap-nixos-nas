{ config, pkgs, ... }:

{
  # SMART 磁盘监控
  services.smartd = {
    enable = true;
    autodetect = true;

    # 监控配置
    defaults.monitored = "-a -o on -s (S/../.././02|L/../../7/04)";

    # 邮件通知（可选，需要配置 MTA）
    notifications = {
      mail = {
        enable = false;  # 默认禁用，需要时启用并配置邮箱
        sender = "smartd@ts564.local";
        recipient = "admin@example.com";
      };
      # 使用 wall 通知到所有登录用户
      wall.enable = true;
    };
  };

  # 定期检查磁盘健康
  systemd.services.smart-health-check = {
    description = "Check disk SMART health";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.smartmontools}/bin/smartctl --all --json /dev/sda";
    };
  };

  systemd.timers.smart-health-check = {
    description = "Daily SMART health check";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "daily";
      Persistent = true;
    };
  };
}
