{
  config,
  lib,
  pkgs,
  ...
}:

let
  hermesCfg = config.services.hermes-agent;
  hermesHome = "${hermesCfg.stateDir}/.hermes";
  hermesPackage = hermesCfg.package;
  workspaceImage = "ghcr.io/outsourc-e/hermes-workspace@sha256:d0bcda667d5e24faafd26132026891b627e3cd451b399642ffd0608af40a2e49";
  workspacePasswd = pkgs.writeText "hermes-workspace-passwd" ''
    root:x:0:0:root:/root:/bin/bash
    daemon:x:1:1:daemon:/usr/sbin:/usr/sbin/nologin
    bin:x:2:2:bin:/bin:/usr/sbin/nologin
    sys:x:3:3:sys:/dev:/usr/sbin/nologin
    sync:x:4:65534:sync:/bin:/bin/sync
    games:x:5:60:games:/usr/games:/usr/sbin/nologin
    man:x:6:12:man:/var/cache/man:/usr/sbin/nologin
    lp:x:7:7:lp:/var/spool/lpd:/usr/sbin/nologin
    mail:x:8:8:mail:/var/mail:/usr/sbin/nologin
    news:x:9:9:news:/var/spool/news:/usr/sbin/nologin
    uucp:x:10:10:uucp:/var/spool/uucp:/usr/sbin/nologin
    proxy:x:13:13:proxy:/bin:/usr/sbin/nologin
    www-data:x:33:33:www-data:/var/www:/usr/sbin/nologin
    backup:x:34:34:backup:/var/backups:/usr/sbin/nologin
    list:x:38:38:Mailing List Manager:/var/list:/usr/sbin/nologin
    irc:x:39:39:ircd:/run/ircd:/usr/sbin/nologin
    _apt:x:42:65534::/nonexistent:/usr/sbin/nologin
    nobody:x:65534:65534:nobody:/nonexistent:/usr/sbin/nologin
    node:x:1000:1000::/home/node:/bin/bash
    workspace:x:999:999::/home/workspace:/bin/bash
  '';
in
{
  # Hermes Workspace needs the gateway HTTP API. Keep it loopback-only; this is a
  # local control-plane UI, not a public service.
  services.hermes-agent.environment = {
    API_SERVER_ENABLED = "true";
    API_SERVER_HOST = "127.0.0.1";
  };

  systemd.services.hermes-dashboard = {
    description = "Hermes Agent Dashboard API";
    wantedBy = [ "multi-user.target" ];
    wants = [
      "network-online.target"
      "hermes-agent.service"
    ];
    after = [
      "network-online.target"
      "hermes-agent.service"
    ];

    path = [
      hermesPackage
      pkgs.coreutils
      pkgs.bashInteractive
    ]
    ++ hermesCfg.extraPackages;

    environment = hermesCfg.environment // {
      HERMES_HOME = hermesHome;
      HERMES_MANAGED = "true";
      HOME = hermesCfg.stateDir;
      PYTHONPATH = lib.mkForce (toString pkgs.opusCtypesShim);
    };

    serviceConfig = {
      User = "hermes";
      Group = "hermes";
      WorkingDirectory = hermesCfg.workingDirectory;
      EnvironmentFile = hermesCfg.environmentFiles;
      ExecStart = "${hermesPackage}/bin/hermes dashboard --host 127.0.0.1 --port 9119 --no-open";
      Restart = "always";
      RestartSec = 5;
      UMask = "0007";
      PrivateTmp = true;
      NoNewPrivileges = true;
      ProtectHome = false;
      ProtectSystem = "strict";
      ReadWritePaths = [
        hermesCfg.stateDir
        hermesCfg.workingDirectory
      ];
    };
  };

  virtualisation.oci-containers = {
    backend = "docker";
    containers.hermes-workspace = {
      image = workspaceImage;
      autoStart = true;
      user = "999:999";
      environment = {
        HOME = "/home/workspace";
        LOGNAME = "workspace";
        SHELL = "/bin/bash";
        HOST = "127.0.0.1";
        PORT = "3000";
        USER = "workspace";
        HERMES_HOME = "/home/workspace/.hermes";
        HERMES_WORKSPACE_DIR = "/workspace";
        HERMES_API_URL = "http://127.0.0.1:8642";
        HERMES_DASHBOARD_URL = "http://127.0.0.1:9119";
        COOKIE_SECURE = "0";
      };
      volumes = [
        "${workspacePasswd}:/etc/passwd:ro"
        "${hermesHome}:/home/workspace/.hermes"
        "${hermesCfg.workingDirectory}:/workspace"
      ];
      extraOptions = [ "--network=host" ];
    };
  };

  systemd.services.docker-hermes-workspace = {
    wants = [
      "hermes-agent.service"
      "hermes-dashboard.service"
    ];
    after = [
      "hermes-agent.service"
      "hermes-dashboard.service"
    ];
  };
}
