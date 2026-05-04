# treefmt configuration — multi-language formatter for `nix fmt`
# Auto-discovers project root via projectRootFile.
# Add/remove programs as needed; `nix fmt` formats all configured types.
{ pkgs, ... }:
{
  projectRootFile = "flake.nix";

  programs.nixfmt.enable = true;
  programs.nixfmt.package = pkgs.nixfmt-rfc-style;

  # Also enable deadnix to clean up nix files (remove dead code, format shebangs).
  # Run separately: `deadnix -f` for format, `deadnix -w` for format+write.
  programs.deadnix.enable = true;
}
