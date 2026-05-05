{ bash, bun, bun2nix, lib, symlinkJoin }:

let
  manifest = builtins.fromJSON (builtins.readFile ./package-manifest.json);
  packageVersion =
    manifest.package.version
    + lib.optionalString (manifest.package ? packageRevision) "-r${toString manifest.package.packageRevision}";
  licenseMap = {
    "MIT" = lib.licenses.mit;
    "Apache-2.0" = lib.licenses.asl20;
    "SEE LICENSE IN README.md" = lib.licenses.unfree;
  };
  resolvedLicense =
    if builtins.hasAttr manifest.meta.licenseSpdx licenseMap
    then licenseMap.${manifest.meta.licenseSpdx}
    else lib.licenses.unfree;
  aliasSpecs = map (
    alias:
    if builtins.isString alias then
      {
        name = alias;
        args = [ ];
      }
    else
      alias
  ) (manifest.binary.aliases or [ ]);
  renderAliasArgs = args: lib.concatMapStringsSep " " lib.escapeShellArg args;
  aliasOutputLinks = lib.concatMapStrings (
    alias:
    ''
      mkdir -p "${"$" + alias.name}/bin"
      cat > "${"$" + alias.name}/bin/${alias.name}" <<EOF
#!${lib.getExe bash}
exec "$out/bin/${manifest.binary.name}" ${renderAliasArgs alias.args} "\$@"
EOF
      chmod +x "${"$" + alias.name}/bin/${alias.name}"
    ''
  ) aliasSpecs;
  src = lib.fileset.toSource {
    root = ../.;
    fileset = lib.fileset.unions [
      ../package.json
      ../bun.lock
    ];
  };
  bunDeps = bun2nix.fetchBunDeps {
    bunNix = ../bun.nix;
  };
  basePackage = bun2nix.mkDerivation {
    pname = manifest.binary.name;
    version = packageVersion;
    inherit src bunDeps;
    module = "node_modules/${manifest.package.npmName}/${manifest.binary.entrypoint}";
    bunCompileToBytecode = false;
    postInstall = ''
      pkgDir="node_modules/${manifest.package.npmName}"
      # Separate dist for assets not part of compiled binary
      distDir="$out/libexec/${manifest.binary.name}/dist"
      mkdir -p "$distDir"

      if [ -d "$pkgDir/dist" ]; then
        cp -r "$pkgDir/dist/." "$distDir/"
        # Support compiled binary layout (looks for assets relative to binary)
        cp -r "$pkgDir/dist/modes/interactive/theme" "$distDir/theme"
        cp -r "$pkgDir/dist/modes/interactive/assets" "$distDir/assets"
        cp -r "$pkgDir/dist/core/export-html" "$distDir/export-html"
      fi
      if [ -d "node_modules" ]; then
        cp -r node_modules "$distDir/node_modules"
      fi
      cp "$pkgDir/package.json" "$distDir/package.json"
      if [ -d "$pkgDir/src/modes/interactive/assets" ]; then
        mkdir -p "$distDir/src/modes/interactive"
        cp -r "$pkgDir/src/modes/interactive/assets" "$distDir/src/modes/interactive/assets"
      fi

      # Move the compiled binary to the dist directory so it can find assets relatively
      mv "$out/bin/${manifest.binary.name}" "$distDir/${manifest.binary.name}"

      # Leave bin/bun in libexec
      mkdir -p "$out/libexec/bin"
      cat > "$out/libexec/bin/bun" <<EOF
#!${lib.getExe bash}
if [ "\$1" = "root" ] && [ "\$2" = "-g" ]; then
  printf '%s\n' "$out/share/${manifest.package.repo}/global/node_modules"
  exit 0
fi
exec ${lib.getExe' bun "bun"} "\$@"
EOF
      chmod +x "$out/libexec/bin/bun"

      # Main wrapper in bin/
      mkdir -p "$out/bin"
      cat > "$out/bin/${manifest.binary.name}" <<EOF
#!${lib.getExe bash}
export PATH="$out/libexec/bin\''${PATH:+:\$PATH}"
export PI_PACKAGE_DIR="$distDir"
exec "$distDir/${manifest.binary.name}" "\$@"
EOF
      chmod +x "$out/bin/${manifest.binary.name}"

      mkdir -p "$out/share/${manifest.package.repo}/global/node_modules"
    '';
    meta = with lib; {
      description = manifest.meta.description;
      homepage = manifest.meta.homepage;
      license = resolvedLicense;
      mainProgram = manifest.binary.name;
      platforms = platforms.linux ++ platforms.darwin;
    };
  };
in
symlinkJoin {
  pname = manifest.binary.name;
  version = packageVersion;
  name = "${manifest.binary.name}-${packageVersion}";
  outputs = [ "out" ] ++ map (alias: alias.name) aliasSpecs;
  paths = [ basePackage ];
  postBuild = ''
    ${aliasOutputLinks}
  '';
  meta = basePackage.meta;
}
