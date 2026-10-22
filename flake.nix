{
  description = "GlobalProtect-openconnect 3.1.0 (gpclient + gpauth, built from source) for NixOS";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forAll = f: nixpkgs.lib.genAttrs systems (s: f nixpkgs.legacyPackages.${s});
    in {
      overlays.default = final: prev:
        let
          gpauth = prev.gpauth.overrideAttrs (old: rec {
            version = "3.1.0";
            src = final.fetchFromGitHub {
              owner = "yuezk";
              repo = "GlobalProtect-openconnect";
              tag = "v${version}"; # tag object 21df6aab, commit 4faa2ecb0d13
              hash = "sha256-0sB/u3Dv6G5VQMhFBoTJNxdwqFDLGgWCAAfrL5IgYIs=";
              fetchSubmodules = true;
            };
            cargoDeps = final.rustPlatform.fetchCargoVendor {
              inherit src;
              name = "gpauth-${version}";
              hash = "sha256-QkUl87XejDpujdTZhsStSRZqban0H5oxhgMZoLLvKEU=";
            };
          });
        in {
          inherit gpauth;
          gpclient = (prev.gpclient.override { inherit gpauth; }).overrideAttrs (old: {
            inherit (gpauth) version src cargoDeps;

            # Upstream tag v3.1.0 -> commit 4faa2ecb0d13 (matches the Debian build).
            env = (old.env or { }) // { GPCLIENT_GIT_COMMIT = "4faa2ecb0d136ea5cf2eec27d067219cb1f0fb6b"; };

            # Needs coreutils at /usr/bin, which the Nix sandbox lacks.
            checkFlags = (old.checkFlags or [ ]) ++ [
              "--skip=embedded_collector_reports_missing_helpers_without_recursing_or_exposing_private_environment"
            ];

            # 3.x reworked the hard-coded paths (HIP is built in, no more
            # hipreport.sh), so the nixpkgs 2.6.x postPatch/postInstall
            # no longer apply. Re-point the Linux release paths at $out.
            postPatch = ''
              substituteInPlace crates/openconnect/src/vpn_utils.rs \
                --replace-fail '"/usr/local/libexec/gpclient/vpnc-script"' "\"$out/libexec/gpclient/vpnc-script\"" \
                --replace-fail '"/usr/libexec/gpclient/vpnc-script"' "\"$out/libexec/gpclient/vpnc-script\""

              substituteInPlace crates/common/src/constants.rs \
                --replace-fail /usr/libexec/gpclient/ $out/libexec/gpclient/ \
                --replace-fail /usr/bin/gpauth ${gpauth}/bin/gpauth \
                --replace-fail /usr/bin/gpclient $out/bin/gpclient \
                --replace-fail /usr/bin/gpservice $out/bin/gpservice \
                --replace-fail /usr/bin/gpgui-helper $out/bin/gpgui-helper \
                --replace-fail /usr/bin/gpgui $out/bin/gpgui
            '';

            postInstall = with final; ''
              mkdir -p $out/libexec/gpclient
              install -m755 packaging/files/usr/libexec/gpclient/vpnc-script $out/libexec/gpclient/vpnc-script
              substituteInPlace $out/libexec/gpclient/vpnc-script \
                --replace-fail /sbin/resolvconf ${openresolv}/bin/resolvconf \
                --replace-fail /usr/bin/resolvectl ${systemd}/bin/resolvectl \
                --replace-fail /usr/bin/busctl ${systemd}/bin/busctl
              wrapProgram $out/libexec/gpclient/vpnc-script \
                --prefix PATH : ${lib.makeBinPath [ coreutils gawk gnugrep gnused nettools unixtools.ps iproute2 openresolv ]}

              cp -r packaging/files/usr/lib $out/lib
              substituteInPlace $out/lib/NetworkManager/dispatcher.d/pre-down.d/gpclient.down \
                --replace-fail /usr/bin/gpclient $out/bin/gpclient
              wrapProgram $out/lib/NetworkManager/dispatcher.d/gpclient-nm-hook \
                --prefix PATH : ${lib.makeBinPath [ coreutils gnugrep unixtools.ps ]}
            '';
          });
        };

      packages = forAll (pkgs:
        let o = (pkgs.extend self.overlays.default); in {
          inherit (o) gpclient gpauth;
          default = o.gpclient;
        });
    };
}
