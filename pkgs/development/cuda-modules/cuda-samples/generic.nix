{
  autoAddDriverRunpath,
  backendStdenv,
  cmake,
  cuda-samples,
  cudaVersion,
  fetchFromGitHub,
  fetchpatch,
  hash,
  lib,
  pkg-config,
  symlinkJoin,

  # CUDA dependencies
  cuda_cccl ? null,
  cuda_cudart,
  cuda_nvcc,
  cuda_nvrtc,
  cuda_profiler_api ? null,
  libcublas,
  libcufft,
  libcurand,
  libcusolver,
  libcusparse,
  libnpp,
  libnvjitlink ? null,
  libnvjpeg,

  # Normal dependencies
  skipInsecureOutputs ? true,
  freeimage,
  glfw3,
  util-linux,

  # Graphical dependencies
  libGL,
  libGLU,
  libglut,
  vulkan-headers,
  vulkan-loader,
  xorg,
}@inputs:

let
  inherit (lib) optionals versionAtLeast versionOlder;

  inherit (backendStdenv.hostPlatform.parsed) cpu kernel;
  releasePath = "bin/${cpu.name}/${kernel.name}/release";

  versionInRange =
    v: lo: hi:
    (versionAtLeast v lo) && (v == hi || versionOlder v hi);

  freeimage = throw "use maybeInsecure.freeimage instead";
  freeimageWithIgnoredCVEs = inputs.freeimage.overrideAttrs (prev: {
    meta = prev.meta // {
      knownVulnerabilities = [ ];
    };
  });

  maybeInsecure =
    if skipInsecureOutputs then
      {
        # Since we are skipping the potentially insecure outputs,
        # we can ignore all of the known vulnerabilities in freeimage.
        freeimage = freeimageWithIgnoredCVEs;
        # Make sure that it actually doesn't end up in the outputs.
        disallowedReferences = [ freeimageWithIgnoredCVEs ];
        # Warn the user about where to find the missing files.
        installScript = ''
          mkdir -p $out
          cat <<'EOF' >$out/README
          The cuda-samples package was built with skipInsecureOutputs = true.
          In this mode, we check that the build succeeds, but don't install the
          resulting outputs, because they depend on FreeImage which is insecure.

          If you need access to the outputs, use cuda-samples.insecure-outputs
          instead. You might have to set the NIXPKGS_ALLOW_INSECURE environment
          variable or the permittedInsecurePackages nixpkgs config setting in
          order to successfully build it.
          EOF
        '';
      }
    else
      {
        # Use the unmodified freeimage package, so that the user
        # gets the standard warning about all of the relevant CVEs.
        inherit (inputs) freeimage;
        disallowedReferences = [ ];
        # Actually install stuff
        installScript = ''
          # Install the data files (if any)
          (cd data; find -type f -exec install -vDm 644 {} $out/data/{} \;)

          # Install the compiled executable binaries
          (cd ${releasePath}; find -type f -exec  install -vDm 755 {} $out/bin/{} \;)
        '';
      };
in
backendStdenv.mkDerivation (finalAttrs: {
  strictDeps = true;

  pname = "cuda-samples";
  version = cudaVersion;

  src = fetchFromGitHub {
    owner = "NVIDIA";
    repo = "cuda-samples";
    rev = "v${finalAttrs.version}";
    inherit hash;
  };

  nativeBuildInputs =
    [
      autoAddDriverRunpath
      pkg-config
      util-linux
    ]
    # CMake has to run as a native, build-time dependency for libNVVM samples.
    # However, it's not the primary build tool -- that's still make.
    # As such, we disable CMake's build system.
    ++ optionals (versionAtLeast finalAttrs.version "12.2") [ cmake ];

  dontUseCmakeConfigure = true;

  buildInputs =
    [
      (maybeInsecure.freeimage)
      glfw3

      # Graphical dependencies
      libGL
      libGLU
      libglut
      vulkan-headers
      vulkan-loader
      xorg.libX11

      # CUDA dependencies
      cuda_cudart
      cuda_nvcc
      cuda_nvrtc
      libcublas
      libcufft
      libcurand
      libcusolver
      libcusparse
      libnpp
      libnvjpeg
      cuda_cudart.static
      libcublas.static
      libcufft.static
      libcurand.static
      libcusparse.static
    ]
    ++ optionals (versionAtLeast finalAttrs.version "11.4") [
      cuda_cccl
    ]
    ++ optionals (versionAtLeast finalAttrs.version "11.8") [
      cuda_profiler_api
    ]
    ++ optionals (versionAtLeast finalAttrs.version "12.0") [
      libnvjitlink
    ];

  patches =
    optionals (finalAttrs.version == "11.3") [
      # See https://github.com/NVIDIA/cuda-samples/issues/75.
      (fetchpatch {
        url = "https://github.com/NVIDIA/cuda-samples/commit/5c3ec60faeb7a3c4ad9372c99114d7bb922fda8d.patch";
        hash = "sha256-0XxdmNK9MPpHwv8+qECJTvXGlFxc+fIbta4ynYprfpU=";
      })
    ]
    ++ optionals (versionInRange finalAttrs.version "11.6" "12.0") [
      # See https://github.com/NVIDIA/cuda-samples/pull/190.
      # 'numeric_limits' is not a member of 'std'
      (fetchpatch {
        url = "https://github.com/NVIDIA/cuda-samples/compare/81cf058e306462d615019b6d6eb86977949b2834..cb52ce49a718c0d3e901191ed82451737592e49f.patch";
        hash = "sha256-FD/5a9LVWN0sDfcLKLRynzbziouvfXJ0oLlSRMP5D6s=";
      })
    ];

  enableParallelBuilding = true;

  postPatch =
    let
      brokenSamples =
        optionals (backendStdenv.hostPlatform.system == "x86_64-linux") [
          # The following samples require DriveOS-specific libraries like
          # NvSciBuf and NvSciSync that are not available on linux
          "cudaNvSci" # libnvscibuf.so not found, please install libnvscibuf.so
          "cudaNvSciNvMedia" # cudaNvSciNvMedia is not supported on Linux x86_64

          # The following samples require the cuDLA library,
          # which is only available on aarch64-jetson
          "cuDLAErrorReporting" # cuDLAErrorReporting is not supported on Linux x86_64
          "cuDLALayerwiseStatsHybrid" # cuDLALayerwiseStatsHybrid is not supported on Linux x86_64
          "cuDLALayerwiseStatsStandalone" # cuDLAErrorReporting is not supported on Linux x86_64
          "cuDLAStandaloneMode" # cuDLAStandaloneMode is not supported on Linux x86_64
        ]
        ++ optionals (finalAttrs.version == "12.1") [
          # The include/cuda/std/barrier header provided by cuda_cccl.dev seems
          # to be incompatible with newer versions of GCC according to this post
          # https://forums.developer.nvidia.com/t/cuda-12-1-error-when-building-cuda-samples/246465
          "simpleAWBarrier" # function "operator new" cannot be called with the given argument list
        ]
        ++ optionals (versionOlder finalAttrs.version "11.8") [
          # cuda_profiler_api is required for the following samples
          # but cuda_profiler_api is only available since CUDA 11.8
          "volumeRender" # cuda_profiler_api.h: No such file or directory
        ];
      # TODO: Report upstream? https://github.com/NVIDIA/cuda-samples/issues/264
      missingLibs = [
        # For some reason, these samples (and only these samples)
        # fail to pick up the default library path.
        "cdpAdvancedQuicksort" # Undefined reference to 'cudaStreamCreateWithFlags'
        "cdpBezierTessellation" # Undefined reference to 'cudaFree'
        "cdpQuadtree" # Undefined reference to 'cudaGetParameterBufferV2'
        "cdpSimplePrint" # Undefined reference to 'cudaGetParameterBufferV2'
        "cdpSimpleQuicksort" # Undefined reference to 'cudaStreamCreateWithFlags'
        "conjugateGradientMultiDeviceCG" # Undefined reference to 'cudaCGGetIntrinsicHandle'
        "simpleCUFFT_callback" # undefined reference to `__cudaRegisterLinkedBinary_*_set_callback_cu_*'
      ];

      ifSampleExists = smp: body: ''
        smp=$(find Samples -type d -name "${smp}")
        if [ -d "$smp" ]; then
          ${body}
        fi
      '';
      removeSample =
        smp:
        ifSampleExists smp ''
          echo "Removing broken sample $smp..."
          rm -rf $smp
        '';
      addLibToSample =
        smp:
        ifSampleExists smp ''
          echo "Adding missing library search path to sample $smp..."
          sed 's|^\(LIBRARIES +=\)|\1 -L\''${CUDA_PATH}/lib |' \
            -i $smp/Makefile
        '';
      removeBrokenSamples = concatMapStrings removeSample brokenSamples;
      addMissingLibraries = concatMapStrings addLibToSample missingLibs;

      # By default, a lot of the Samples are just silently skipped when
      # something goes wrong instead of failing. This code modifies the
      # Makefiles so that they fail instead of "waiving samples".
      dontWaiveSamples = ''
        find Samples -type f \( -name "Makefile" -o -name "*.mk" \) -exec sed \
          's|SAMPLE_ENABLED := 0|$(error {}: ERROR, WAIVING NOT ALLOWED)|g' \
          -i "{}" \;
      '';
    in
    removeBrokenSamples + addMissingLibraries + dontWaiveSamples;

  # Set some environment variables to help the poorly written
  # Makefiles find the libraries, headers, etc.
  preConfigure =
    let
      paths = finalAttrs.buildInputs;
      devPaths = map lib.getDev paths;
      libPaths = map lib.getLib paths;
      buildInputsRoot = symlinkJoin {
        name = "build-inputs-root";
        paths = paths ++ devPaths ++ libPaths;
      };
    in
    ''
      export CUDA_PATH=${buildInputsRoot}
      export CUDALIB=${buildInputsRoot}/lib/stubs/libcuda.so
      export DFLT_PATH=${buildInputsRoot}/lib
      export HEADER_SEARCH_PATH=${buildInputsRoot}/include
    '';

  # Any files that were in the release directory before the build started
  # are non-executable data files (raw data, images, helper scripts and
  # expected sample outputs). Move them to ./data in advance to make it
  # easier to distinguish data and executables during the install step.
  preBuild = ''
    mkdir -p ${releasePath}
    mv ${releasePath} data
    mkdir -p ${releasePath}
  '';

  inherit (maybeInsecure) disallowedReferences;
  installPhase = ''
    runHook preInstall
    ${maybeInsecure.installScript}
    runHook postInstall
  '';

  passthru.insecure-outputs = cuda-samples.override {
    skipInsecureOutputs = false;
  };

  meta = {
    description = "Samples for CUDA Developers which demonstrates features in CUDA Toolkit";
    # CUDA itself is proprietary, but these sample apps are not.
    license = lib.licenses.bsd3;
    platforms = [ "x86_64-linux" ];
    maintainers = with lib.maintainers; [ obsidian-systems-maintenance ] ++ lib.teams.cuda.members;
  };
})
