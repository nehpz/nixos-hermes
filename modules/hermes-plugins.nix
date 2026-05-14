{ pkgs, ... }:

let
  # Match Hermes 0.12.0's sealed Python environment. The pinned nixpkgs
  # default is Python 3.13, while the Hermes wrapper currently runs Python 3.12;
  # using pkgs.python3Packages would build plugins for the wrong interpreter.
  pythonPackages = pkgs.python312Packages;

  rtkHermes = pythonPackages.buildPythonPackage rec {
    pname = "rtk-hermes";
    version = "1.2.3";

    src = pkgs.fetchFromGitHub {
      owner = "ogallotti";
      repo = "rtk-hermes";
      rev = "v${version}";
      hash = "sha256-7YRW6PODrCapfYLFn3DvgHAEME//RGC48GQt+s9ot0s=";
    };

    pyproject = true;
    build-system = [ pythonPackages.setuptools ];
    # rtk-hermes declares no mandatory third-party runtime Python dependencies
    # in pyproject.toml. Its runtime integration shells out to the `rtk` binary,
    # which is supplied through services.hermes-agent.extraPackages below.
    dependencies = [ ];

    pythonImportsCheck = [ "rtk_hermes" ];
  };

  hindsightClient = pythonPackages.buildPythonPackage rec {
    pname = "hindsight-client";
    version = "0.5.4";

    src = pkgs.fetchurl {
      url = "https://files.pythonhosted.org/packages/64/69/30c8252e9b6b04876946f05adf8497b1204f90a77f181e2d9c501dcaa317/hindsight_client-0.5.4.tar.gz";
      hash = "sha256-rcs9+zqxqzSmGdJ8OiqRxCUw6hlxSIpgSh2sLHjVVHs=";
    };

    pyproject = true;
    build-system = [ pythonPackages.hatchling ];

    dependencies = [ ];
    dontCheckRuntimeDeps = true;

    # These are already present in the Hermes sealed runtime. Keep them available
    # for this package's build-time import check without propagating duplicate
    # distributions into services.hermes-agent.extraPythonPackages, where the
    # Hermes build intentionally rejects sealed-venv collisions.
    nativeCheckInputs = with pythonPackages; [
      aiohttp
      aiohttp-retry
      pydantic
      python-dateutil
      typing-extensions
      urllib3
    ];

    pythonImportsCheck = [ "hindsight_client" ];
  };
in
{
  services.hermes-agent = {
    # Entry-point plugins are installed into the Hermes Python wrapper via
    # extraPythonPackages. Directory plugins should use extraPlugins instead;
    # see docs/guides/HERMES_PLUGINS_NIX.md for the repeatable workflow.
    extraPythonPackages = [
      rtkHermes
      hindsightClient
    ];

    # rtk-hermes rewrites terminal commands through the rtk binary. Keep the
    # executable in the Hermes service PATH declaratively instead of relying on
    # mutable state in the service home.
    extraPackages = [ pkgs.llm-agents.rtk ];

    settings.plugins.enabled = [
      "rtk-rewrite"
    ];
  };
}
