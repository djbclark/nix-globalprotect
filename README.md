# nix-globalprotect: GlobalProtect-openconnect 3.1.0 for NixOS

A Nix flake that builds [yuezk/GlobalProtect-openconnect](https://github.com/yuezk/GlobalProtect-openconnect)
**3.1.0** (tag `v3.1.0`, commit `4faa2ecb0d13`, the same source as the upstream Debian package
`globalprotect-openconnect 3.1.0-1`) from source, for MIT's GlobalProtect VPN (`gpvpn.mit.edu`) on
headless NixOS machines.

nixos-26.05 ships `gpclient`/`gpauth` 2.6.x. This flake reuses the nixpkgs derivations and only swaps
the source, the vendored Cargo dependencies and the path patches that changed in 3.x.

## Who it is for

Anyone at MIT (SIPB or otherwise) who runs `gpclient` on NixOS and wants the 3.x client: `--browser manual`
(the old `--browser remote` still works), built-in HIP reports (`--hip` without a `hipreport.sh`),
`--cookie-only`, `gpclient diagnostics`.

## Outputs

| Output | What |
|---|---|
| `packages.x86_64-linux.gpclient` (also `default`) | `gpclient` 3.1.0, with the vendored openconnect, `libexec/gpclient/vpnc-script` and the NetworkManager hooks |
| `packages.x86_64-linux.gpauth` | `gpauth` 3.1.0 (webkitgtk SAML helper; `gpclient` has its store path compiled in) |
| `overlays.default` | replaces `gpclient` and `gpauth` in your package set |

`aarch64-linux` is declared but has not been built. `gpservice` and the GUI (`gpgui`) are not packaged: the
headless `sudo gpclient connect` flow does not need them.

## Use

Try it without installing:

```sh
nix run git+https://forgejo.mit.edu/djbclark/nix-globalprotect -- --version
# gpclient 3.1.0 (4faa2ecb0 <build date>)
```

In a NixOS flake (this is how `site-djbclark`'s `nixos/flake.nix` uses it for vps-primary):

```nix
{
  inputs.nix-globalprotect = {
    url = "git+https://forgejo.mit.edu/djbclark/nix-globalprotect";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { nixpkgs, nix-globalprotect, ... }: {
    nixosConfigurations.myhost = nixpkgs.lib.nixosSystem {
      modules = [
        { nixpkgs.overlays = [ nix-globalprotect.overlays.default ]; }
        ./configuration.nix   # keeps listing pkgs.gpclient and pkgs.gpauth as before
      ];
    };
  };
}
```

`inputs.nixpkgs.follows` builds against your nixpkgs; this repository is tested against nixos-26.05.
The overlay changes nothing else, so removing that one line goes back to the nixpkgs 2.6.x client.

Connecting from a headless box, routing only MIT through the tunnel (open the printed URL on your laptop,
finish Touchstone and Duo, paste the callback back):

```sh
sudo gpclient connect gpvpn.mit.edu --browser remote --hip --gateway "US East" \
  --cookie-cache=$HOME/.cache/gp-mit/cookie --script "vpn-slice 18.0.0.0/8"
```

## Build and verify

```sh
nix build .#gpclient && ./result/bin/gpclient --version
nix flake check
```

Verified on x86_64-linux, 2026-10-22: both packages build (the Rust test suites run, see below),
`gpclient --version` prints `gpclient 3.1.0 (4faa2ecb0 ...)`, and `gpclient connect --help` is
identical to the upstream Debian 3.1.0-1 build's.

## What differs from the nixpkgs derivation

1. `src` is tag `v3.1.0` (with submodules: vendored openconnect and libxml2); `cargoDeps` re-vendored.
2. `postPatch`: 3.x no longer has `hipreport.sh` (HIP is built in), and `constants.rs` gained gpgui,
   gpgui-helper and script-installer paths; all Linux `/usr/...` paths point into `$out` (gpauth into its own store path).
3. `postInstall`: installs the upstream `vpnc-script` (resolvconf, resolvectl and busctl pinned to store paths,
   `PATH` wrapped) and the NetworkManager dispatcher hooks.
4. `GPCLIENT_GIT_COMMIT` is set so `--version` names the upstream commit; the date in it is the build date.
5. One upstream test is skipped (`embedded_collector_reports_missing_helpers_...`): it runs `/bin/sh` scripts
   that need `tr`/`mktemp` from `/usr/bin`, which the Nix sandbox does not have.

## Updating to a new upstream release

Bump `version`, set both `hash` values to `lib.fakeHash`, `nix build`, paste the hashes Nix reports, update
`GPCLIENT_GIT_COMMIT`, and fix any `substituteInPlace --replace-fail` that no longer matches.

## What is specific to djbclark

Nothing in the flake. The `gpvpn.mit.edu` command line above (gateway `US East`, `vpn-slice 18.0.0.0/8`)
is the one vps-primary uses; change the gateway and routes for your needs.

License: the packaging is MIT (see `LICENSE`); GlobalProtect-openconnect itself is GPL-3.0.
