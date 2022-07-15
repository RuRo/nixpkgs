{ callPackage, lib, fetchFromGitHub }:

let
  sets = [ "comfy" "comfy-fixed" "comfy-duo" "comfy-wide" "comfy-wide-fixed" ];
  version = "0.2.1";
  src = fetchFromGitHub {
    owner = "protesilaos";
    repo = "iosevka-comfy";
    rev = version;
    sha256 = "sha256-Ki3/8REmVb1XtvchdLZJ9Zc+EoP3LP9tvruuP/K1Xpo=";
  };
  privateBuildPlan = src.outPath + "/private-build-plans.toml";
  overrideAttrs = (attrs: {
    inherit version;

    meta = with lib; {
      homepage = "https://github.com/protesilaos/iosevka-comfy";
      description = ''
      Custom build of Iosevka with a rounded style and open shapes,
      adjusted metrics, and overrides for almost all individual glyphs
      in both roman (upright) and italic (slanted) variants.
    '';
      license = licenses.ofl;
      platforms = attrs.meta.platforms;
      maintainers = [ maintainers.DamienCassou ];
    };
  });
  makeIosevkaFont = set: (callPackage ./. {
    inherit set privateBuildPlan;
  }).overrideAttrs overrideAttrs;
in
builtins.listToAttrs (builtins.map (set: {name=set; value=makeIosevkaFont set;}) sets)
