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

  treeSitterWheel =
    {
      pname,
      version,
      url,
      hash,
      importName,
    }:
    pythonPackages.buildPythonPackage {
      inherit pname version;
      format = "wheel";
      src = pkgs.fetchurl { inherit url hash; };
      doCheck = false;
      pythonImportsCheck = [ importName ];
    };

  # Upstream hermes-code-intel-plugin eagerly imports all grammar modules when
  # initializing tree-sitter languages. Package the missing wheels instead of
  # locally pruning unvalidated languages from upstream source.
  treeSitterTypescript = treeSitterWheel {
    pname = "tree-sitter-typescript";
    version = "0.23.2";
    url = "https://files.pythonhosted.org/packages/49/d1/a71c36da6e2b8a4ed5e2970819b86ef13ba77ac40d9e333cb17df6a2c5db/tree_sitter_typescript-0.23.2-cp39-abi3-manylinux_2_5_x86_64.manylinux1_x86_64.manylinux_2_17_x86_64.manylinux2014_x86_64.whl";
    hash = "sha256-6W02uFvKzeuP9cJhjXVZPvEuuvG06s40d+K9squxdSw=";
    importName = "tree_sitter_typescript";
  };

  treeSitterGo = treeSitterWheel {
    pname = "tree-sitter-go";
    version = "0.25.0";
    url = "https://files.pythonhosted.org/packages/86/fb/b30d63a08044115d8b8bd196c6c2ab4325fb8db5757249a4ef0563966e2e/tree_sitter_go-0.25.0-cp310-abi3-manylinux1_x86_64.manylinux_2_28_x86_64.manylinux_2_5_x86_64.whl";
    hash = "sha256-BLOzy0r/GOdOKNSbcWxvJMtx3f3WZ2iYfibk0PqBL3Q=";
    importName = "tree_sitter_go";
  };

  treeSitterJava = treeSitterWheel {
    pname = "tree-sitter-java";
    version = "0.23.5";
    url = "https://files.pythonhosted.org/packages/29/09/e0d08f5c212062fd046db35c1015a2621c2631bc8b4aae5740d7adb276ad/tree_sitter_java-0.23.5-cp39-abi3-manylinux_2_5_x86_64.manylinux1_x86_64.manylinux_2_17_x86_64.manylinux2014_x86_64.whl";
    hash = "sha256-NwsgS5UAuEf20MWtWEBFgxzuaemj5Nh4U1055KfkxPE=";
    importName = "tree_sitter_java";
  };

  codeIntelPythonPackages = with pythonPackages; [
    ast-grep-py
    tree-sitter
    tree-sitter-python
    tree-sitter-javascript
    treeSitterTypescript
    tree-sitter-rust
    treeSitterGo
    treeSitterJava
  ];

  codeIntelPlugin = pkgs.stdenvNoCC.mkDerivation {
    pname = "hermes-code-intel-plugin";
    version = "2026-05-07";

    src = pkgs.fetchFromGitHub {
      owner = "rewasa";
      repo = "hermes-code-intel-plugin";
      rev = "e949f0a2b9c6b4a64d08f3f0a2da80fe7faae0a4";
      hash = "sha256-yHQEO82lVEI06b4Vp3ud3Xd5oEQE0BdVZ31nFHOx8R4=";
    };

    # Pyright starts in this environment by inferring nixpkgs' default Python
    # 3.13, while Hermes 0.12.0 runs a sealed Python 3.12 runtime. Pyrefly was
    # validated live as a drop-in Python LSP for definition/reference lookups.
    postPatch = ''
      substituteInPlace lsp_bridge.py \
        --replace-fail 'pyright-langserver", "args": ["--stdio"]' 'pyrefly", "args": ["lsp"]'
      substituteInPlace lsp_bridge.py \
        --replace-fail 'pyright-langserver — excellent type resolution (via pyright npm/pip)' 'pyrefly — fast Rust Python type checker and LSP'
    '';

    installPhase = ''
      runHook preInstall
      mkdir -p $out
      cp -R . $out/
      runHook postInstall
    '';
  };
in
{
  services.hermes-agent = {
    # Entry-point plugins are installed into the Hermes Python wrapper via
    # extraPythonPackages. Directory plugins should use extraPlugins instead;
    # see docs/guides/HERMES_PLUGINS_NIX.md for the repeatable workflow.
    extraPythonPackages = [ rtkHermes ] ++ codeIntelPythonPackages;

    # Directory-style plugins are added to Hermes' plugin search path. For
    # code_intel, keep upstream behavior intact and satisfy its eager deps;
    # only the Python LSP command is patched from Pyright to Pyrefly above.
    extraPlugins = [ codeIntelPlugin ];

    extraPackages = [
      # rtk-hermes rewrites terminal commands through the rtk binary. Keep the
      # executable in the Hermes service PATH declaratively instead of relying
      # on mutable state in the service home.
      pkgs.llm-agents.rtk

      # code_intel runtime tools. `pkgs.pyrefly` is top-level in this pin;
      # there is no `pkgs.llm-agents.pyrefly`.
      pkgs.ast-grep
      pkgs.pyrefly
      pkgs.typescript-language-server
    ];

    settings.plugins.enabled = [
      "rtk-rewrite"
      "code_intel"
    ];
  };
}
