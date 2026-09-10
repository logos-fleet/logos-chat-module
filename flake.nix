{
  description = "Logos Chat Module";

  # Pull pre-built artifacts (delivery module, liblogosdelivery, …) from the
  # self-hosted Logos Attic cache, for local builds too — CI configures its
  # substituters itself. Read-only and public; see infra-ci#263. Only the
  # public (master-built) cache belongs here; ci is CI-only by design.
  nixConfig = {
    extra-substituters = [ "https://cache.nix.logos.co/public" ];
    extra-trusted-public-keys = [ "public:l4HrXgL4nw246+LBh2SOJyhz64BoGegOYLheT/iIAPU=" ];
  };

  inputs = {
    # STILL HELD AT 0.2.6, and the reason is now measured rather than assumed:
    # a current builder's logos-rust-sdk emits declared records as typed Rust
    # structs (`Status`, `Conversation`, `Message`, `GroupMember`) where the
    # providers in rust-lib/src/lib.rs return `serde_json::Value` -- 5x E0053.
    # Moving the pin means adapting those five providers in the same change.
    #
    # The mobile Bare outputs exposed below are a property of the BUILDER, so
    # they appear the moment this pin moves and are absent (not broken) until
    # then -- `mobileTargets` below is empty on a builder that has none.
    logos-module-builder.url = "github:logos-co/logos-module-builder/0.2.6";

    # Pinned to the v0.2.0 release tag (Reliable Channels API, storeQuery,
    # layered createNode config; the flat config shape this module sends still
    # parses). Kept in lockstep with logos-chat-ui's pin.
    logos-delivery-module.url = "github:logos-co/logos-delivery-module/v0.2.0";
  };

  outputs = inputs@{ self, logos-module-builder, logos-delivery-module, ... }:
    let
      nixpkgs = logos-module-builder.inputs.nixpkgs;
      systems = [ "aarch64-darwin" "x86_64-darwin" "aarch64-linux" "x86_64-linux" ];
      forAllSystems = fn: nixpkgs.lib.genAttrs systems fn;

      # The builder runs logos-lidl-gen to emit the module-impl C ABI scaffold
      # (the `ChatModule` trait + logos_module_* exports) at rust-lib/generated/,
      # compiles the staticlib, and stages it — all driven by
      # metadata.json#codegen.rust. No build.rs, no per-flake buildRustPackage.
      #
      # Not a function of the system: mkLogosModule answers for EVERY target it
      # knows at once, and building it per system only threw four copies away.
      module = logos-module-builder.lib.mkLogosModule {
        src = ./.;
        configFile = ./metadata.json;
        flakeInputs = {
          delivery_module = logos-delivery-module;
        } // inputs;
      };

      # The mobile pseudo-systems the builder adds to `packages` when its
      # logos-nix carries the cross sets. Kept out of `systems` above for the
      # reason the builder keeps them out of its own: a phone gets the Bare
      # module and none of the other twenty outputs. `? ${t}` rather than a bare
      # index, so a builder without them is simply a flake without mobile keys.
      mobileTargets = builtins.filter (t: module.packages ? ${t})
        [ "aarch64-ios" "aarch64-ios-simulator" "aarch64-android" ];
    in
    {
      packages = forAllSystems (system:
        let m = module.packages.${system};
        in m // {
          # CI builds `.#chat_module`; alias it to the plugin package. The full
          # set `m` (default, install, lidl, …) is exposed too, so the UI module
          # can consume chat_module's published .lidl contract.
          chat_module = m.default;

          # The matching delivery_module .lgx, re-exported from this flake's
          # locked delivery input, so the exact delivery_module rev chat_module is
          # built against can be installed alongside it.
          "delivery_module-lgx" = logos-delivery-module.packages.${system}.lgx;
        })
      # nix build .#packages.aarch64-ios.bare — the chat core cross-compiled and
      # whole-archived into a protocol-free image an iOS app or an APK loads.
      // nixpkgs.lib.genAttrs mobileTargets (t: module.packages.${t});

      # An Android derivation's `system` is its BUILD platform, so
      # `packages.aarch64-android` is pinned to the builder's canonical one
      # (x86_64-linux) and a Mac cannot realise it. This is the same artifact
      # built from the other one:
      #   nix build .#legacyPackages.aarch64-darwin.mobile.aarch64-android.bare
      legacyPackages = module.legacyPackages or { };

      # `nix run .#generate` materialises the two gitignored inputs `rust-lib/`
      # references into the working tree, both from the rev the builder pins: the
      # provider scaffold (logos-lidl-gen over chat_module.lidl) at
      # rust-lib/generated/, and the SDK source the crate path-deps as
      # `../logos-rust-sdk-src`. After it, bare `cargo build/test/clippy` works in
      # rust-lib/ directly, with no staged copy.
      apps = forAllSystems (system:
        let
          pkgs = import nixpkgs { inherit system; };
          lidlGen = logos-module-builder.inputs.logos-rust-sdk.packages.${system}.lidl-gen;
          sdkSrc = logos-module-builder.packages.${system}.rust-sdk-src;
          generate = pkgs.writeShellApplication {
            name = "chat-module-generate";
            runtimeInputs = [ lidlGen pkgs.git ];
            text = ''
              root="$(git rev-parse --show-toplevel)"
              echo "generating rust-lib/generated/provider_gen.rs ..."
              mkdir -p "$root/rust-lib/generated"
              logos-lidl-gen "$root/rust-lib/chat_module.lidl" --provider \
                --dep delivery_module="$root/rust-lib/deps/delivery_module.lidl" \
                -o "$root/rust-lib/generated/provider_gen.rs"
              echo "staging the SDK source at logos-rust-sdk-src/ ..."
              rm -rf "''${root:?}/logos-rust-sdk-src"
              cp -RL "${sdkSrc}" "$root/logos-rust-sdk-src"
              chmod -R u+w "$root/logos-rust-sdk-src"
              echo "done. bare 'cargo build' now works in rust-lib/"
            '';
          };
        in {
          generate = {
            type = "app";
            program = "${generate}/bin/chat-module-generate";
          };
        });

      # Build tools for bare `cargo` (clippy/test) that the module build needs but
      # the CI runner image lacks: `protobuf` (protoc) for hashgraph-like-consensus's
      # prost-build build script. Sourced from the same pinned nixpkgs as the nix
      # build (metadata.json#nix.rust.packages.build), so `nix develop --command
      # cargo …` uses the repo's own pin, not a separate toolchain.
      devShells = forAllSystems (system:
        let pkgs = import nixpkgs { inherit system; };
        in {
          default = pkgs.mkShell {
            packages = [ pkgs.protobuf ];
          };
        });
    };
}
