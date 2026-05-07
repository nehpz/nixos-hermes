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

  codeIntelPlugin = pkgs.stdenvNoCC.mkDerivation {
    pname = "hermes-code-intel-plugin";
    version = "2026-05-01";

    src = pkgs.fetchFromGitHub {
      owner = "rewasa";
      repo = "hermes-code-intel-plugin";
      rev = "e949f0a2b9c6b4a64d08f3f0a2da80fe7faae0a4";
      hash = "sha256-yHQEO82lVEI06b4Vp3ud3Xd5oEQE0BdVZ31nFHOx8R4=";
    };

    patchPhase = ''
      runHook prePatch
      sed -i \
        -e '/tree_sitter_typescript as tsts/d' \
        -e '/tree_sitter_go as tsgo/d' \
        -e '/tree_sitter_java as tsjava/d' \
        -e '/language_typescript/d' \
        -e '/language_tsx/d' \
        -e '/tsgo\.language/d' \
        -e '/tsjava\.language/d' \
        code_intel.py

      # Keep the pilot narrow: expose the explicit `code_intel` toolset, but do
      # not inject code-intel into core toolsets, subagent defaults, builtin
      # tool descriptions, or every coding prompt until runtime behavior is
      # boringly stable.
      sed -i \
        -e '/# C2: pre_llm_call hook/,/ctx.register_hook("pre_llm_call"/d' \
        -e '/# Inject into core platforms/,/    # Load our tools/{ /    # Load our tools/!d }' \
        -e '/# Inject steering hints directly into the registry schemas/,$d' \
        __init__.py

      # Prefer Pyrefly over Pyright for Python LSP in the MVP. Pyright worked
      # for smoke tests but inferred Python 3.13 while Hermes 0.12.0 runs on
      # Python 3.12; Pyrefly is a smaller Rust binary and avoids that mismatch.
      sed -i \
        -e 's/# pyright-langserver — excellent type resolution (via pyright npm\/pip)/# pyrefly — fast Rust Python type checker and LSP/' \
        -e 's#{"command": "pyright-langserver", "args": \["--stdio"\], "language_id": "python"}#{"command": "pyrefly", "args": ["lsp"], "language_id": "python"}#' \
        lsp_bridge.py
      runHook postPatch
    '';

    installPhase = ''
      runHook preInstall
      mkdir -p $out
      cp -R . $out/
      runHook postInstall
    '';
  };

  # Python-first code-intel MVP. The pinned nixpkgs package set has Python,
  # JavaScript, and Rust tree-sitter grammars; TypeScript/Go/Java bindings need
  # follow-up packaging work because their PyPI sdists expect tree_sitter/parser.h.
  codeIntelPythonPackages = with pythonPackages; [
    ast-grep-py
    tree-sitter
    tree-sitter-python
    tree-sitter-javascript
    tree-sitter-rust
  ];
in
{
  services.hermes-agent = {
    # Entry-point plugins are installed into the Hermes Python wrapper via
    # extraPythonPackages. Directory plugins should use extraPlugins instead;
    # see docs/guides/HERMES_PLUGINS_NIX.md for the repeatable workflow.
    extraPythonPackages = [ rtkHermes ] ++ codeIntelPythonPackages;
    extraPlugins = [ codeIntelPlugin ];

    # Runtime binaries scoped to the Hermes service: rtk for rtk-hermes, plus
    # the narrow Python/Rust code-intel MVP tools. TypeScript and Go LSPs stay
    # out until their tree-sitter grammars are packaged and validated.
    extraPackages = [
      pkgs.llm-agents.rtk
      pkgs.ast-grep
      pkgs.pyrefly
      pkgs.rust-analyzer
    ];

    settings.plugins.enabled = [
      "rtk-rewrite"
      "code_intel"
    ];
  };
}
