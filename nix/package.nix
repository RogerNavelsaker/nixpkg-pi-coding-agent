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
      local pkgDir="node_modules/${manifest.package.npmName}"
      mkdir -p "$out/libexec"
      if [ -d "$pkgDir/dist" ]; then
        cp -r "$pkgDir/dist/." "$out/libexec/"
      fi
      if [ -d "node_modules" ]; then
        cp -r node_modules "$out/libexec/node_modules"
      fi
      mv "$out/bin/${manifest.binary.name}" "$out/libexec/${manifest.binary.name}"
      cp "$pkgDir/package.json" "$out/libexec/package.json"
      if [ -d "$pkgDir/src/modes/interactive/assets" ]; then
        mkdir -p "$out/libexec/src/modes/interactive"
        cp -r "$pkgDir/src/modes/interactive/assets" "$out/libexec/src/modes/interactive/assets"
      fi
      mkdir -p "$out/share/${manifest.package.repo}/global/node_modules"
      cat > "$out/libexec/bun" <<EOF
#!${lib.getExe bash}
if [ "\$1" = "root" ] && [ "\$2" = "-g" ]; then
  printf '%s\n' "$out/share/${manifest.package.repo}/global/node_modules"
  exit 0
fi
exec ${lib.getExe' bun "bun"} "\$@"
EOF
      chmod +x "$out/libexec/bun"
      cat > "$out/bin/${manifest.binary.name}" <<EOF
#!${lib.getExe bash}
export PATH="$out/libexec''${PATH:+:$PATH}"
exec "$out/libexec/${manifest.binary.name}" "\$@"
EOF
      chmod +x "$out/bin/${manifest.binary.name}"
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
