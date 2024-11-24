{ lib
, python
, makePythonHook
, makeWrapper }:

makePythonHook {
      name = "wrap-python-hook";
      propagatedBuildInputs = [ makeWrapper ];
      substitutions.sitePackages = python.sitePackages;
      substitutions.executable = python.interpreter;
      substitutions.python = python.pythonOnBuildForHost;
      substitutions.pythonHost = python;
      substitutions.magicalSedExpression = let
        # Looks weird? Of course, it's between single quoted shell strings.
        # NOTE: Order DOES matter here, so single character quotes need to be
        #       at the last position.
        quoteVariants = [ "'\"'''\"'" "\"\"\"" "\"" "'\"'\"'" ]; # hey Vim: ''

        mkStringSkipper = labelNum: quote: let
          label = "q${toString labelNum}";
          isSingle = lib.elem quote [ "\"" "'\"'\"'" ];
          endQuote = if isSingle then "[^\\\\]${quote}" else quote;
        in ''
          /^[a-z]?${quote}/ {
            /${quote}${quote}|${quote}.*${endQuote}/{n;br}
            :${label}; n; /^${quote}/{n;br}; /${endQuote}/{n;br}; b${label}
          }
        '';

        # This preamble does two things:
        # * Sets argv[0] to the original application's name; otherwise it would be .foo-wrapped.
        #   Python doesn't support `exec -a`.
        # * Adds all required libraries to sys.path via `site.addsitedir`. It also handles *.pth files.
        preamble = ''
          import sys
          import site
          import functools
          import os
          print('"'argv0: '"' + sys.orig_argv[0] + '"' target: '"' + '"'$f'"' + '"' verdict: '"', end="")
          _nix_wrapped = '"'$f'"'.split('"'/'"')
          _nix_direct = os.path.realpath(sys.orig_argv[0]) == '"'/'"'.join([*_nix_wrapped[:-1], '"'''"'.join(['"'.'"', _nix_wrapped[-1], '"'-wrapped'"']) ]) or os.path.realpath(sys.argv[0]) == '"'$f'"'
          sys.orig_argv[0] = '"'$(readlink -f "$f")'"' if _nix_direct else sys.argv[0]
          functools.reduce(lambda k, p: site.addsitedir(p, k), ['"$([ -n "$program_PYTHONPATH" ] && (echo "'$program_PYTHONPATH'" | sed "s|:|','|g") || true)"'], site._init_pathinfo()) if _nix_direct else None
          print(str(_nix_direct))
        '';

      in ''
        1 {
          :r
          /\\$|,$/{N;br}
          /__future__|^ |^ *(#.*)?$/{n;br}
          ${lib.concatImapStrings mkStringSkipper quoteVariants}
          /^[^# ]/i ${lib.replaceStrings ["\n"] [";"] preamble}
        }
      '';
} ./wrap.sh
