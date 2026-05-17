# Host-local Agent Memory parallel-observer service.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.agentmemory;
  stateDir = "/var/lib/agentmemory";
  restPort = 3111;
  streamsPort = 3112;
  viewerPort = 3113;
  enginePort = 49134;
in
{
  options.services.agentmemory = {
    enable = lib.mkEnableOption "Agent Memory local parallel-observer service";

    package = lib.mkPackageOption pkgs "agentmemory" { };
  };

  config = lib.mkMerge [
    {
      services.agentmemory.enable = lib.mkDefault true;
    }

    (lib.mkIf cfg.enable {
      users.users.agentmemory = {
        isSystemUser = true;
        group = "agentmemory";
        home = stateDir;
        createHome = false;
      };

      users.groups.agentmemory = { };

      systemd.services.agentmemory = {
        description = "Agent Memory parallel observer";
        after = [ "network.target" ];
        wantedBy = [ "multi-user.target" ];

        environment = {
          HOME = stateDir;
          AGENTMEMORY_URL = "http://127.0.0.1:${toString restPort}";
          AGENTMEMORY_VIEWER_URL = "http://127.0.0.1:${toString viewerPort}";
          AGENTMEMORY_ALLOW_AGENT_SDK = "false";
          AGENTMEMORY_AUTO_COMPRESS = "false";
          GRAPH_EXTRACTION_ENABLED = "false";
          CONSOLIDATION_ENABLED = "false";
          AGENTMEMORY_INJECT_CONTEXT = "false";
          AGENTMEMORY_TOOLS = "core";
          AGENTMEMORY_III_VERSION = cfg.package.passthru.iii-engine.version;
          III_REST_PORT = toString restPort;
          III_STREAMS_PORT = toString streamsPort;
          III_STREAM_PORT = toString streamsPort;
          III_VIEWER_PORT = toString viewerPort;
          III_ENGINE_URL = "ws://127.0.0.1:${toString enginePort}";
          VIEWER_ALLOWED_ORIGINS = "http://127.0.0.1:${toString restPort},http://127.0.0.1:${toString viewerPort},http://localhost:${toString restPort},http://localhost:${toString viewerPort}";
        };

        path = [
          cfg.package.passthru.iii-engine
          pkgs.coreutils
        ];

        serviceConfig = {
          Type = "simple";
          User = "agentmemory";
          Group = "agentmemory";
          StateDirectory = "agentmemory";
          StateDirectoryMode = "0700";
          WorkingDirectory = stateDir;
          ExecStart = "${lib.getExe cfg.package} --tools core";
          Restart = "on-failure";
          RestartSec = "5s";

          NoNewPrivileges = true;
          PrivateTmp = true;
          ProtectSystem = "strict";
          ProtectHome = true;
          ReadWritePaths = [ stateDir ];
          RestrictAddressFamilies = [
            "AF_UNIX"
            "AF_INET"
            "AF_INET6"
          ];
        };
      };
    })
  ];
}
