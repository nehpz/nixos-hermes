{
  stdenv,
  fetchurl,
  autoPatchelfHook,
  lib,
}:

# agent-browser ships prebuilt platform binaries inside the npm tarball.
# We select the binary for the current platform; no build toolchain needed.
let
  platformBinary =
    {
      "x86_64-linux" = "agent-browser-linux-x64";
      "aarch64-linux" = "agent-browser-linux-arm64";
      "aarch64-darwin" = "agent-browser-darwin-arm64";
      "x86_64-darwin" = "agent-browser-darwin-x64";
    }
    .${stdenv.hostPlatform.system}
      or (throw "agent-browser: unsupported platform ${stdenv.hostPlatform.system}");
in
stdenv.mkDerivation rec {
  pname = "agent-browser";
  version = "0.26.0";

  src = fetchurl {
    url = "https://registry.npmjs.org/agent-browser/-/agent-browser-${version}.tgz";
    sha256 = "1gslz3i5z0ywy1fz0dxm0hba7pxb1dgd5mn4q492rp6p210wyj4a";
  };

  # npm tarballs extract to package/
  sourceRoot = "package";

  # autoPatchelfHook rewrites ELF interpreter paths — Linux only.
  nativeBuildInputs = lib.optionals stdenv.hostPlatform.isLinux [ autoPatchelfHook ];

  dontBuild = true;
  dontConfigure = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin
    cp bin/${platformBinary} $out/bin/agent-browser
    chmod +x $out/bin/agent-browser
    runHook postInstall
  '';

  meta = {
    description = "Headless browser automation CLI for AI agents";
    homepage = "https://github.com/vercel-labs/agent-browser";
    license = lib.licenses.asl20;
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
      "aarch64-darwin"
      "x86_64-darwin"
    ];
    mainProgram = "agent-browser";
  };
}
