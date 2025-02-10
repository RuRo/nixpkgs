{
  autoAddDriverRunpath,
  backendStdenv,
  cmake,
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
}:
let
  inherit (lib) optionals versionAtLeast versionOlder;

  inherit (backendStdenv.hostPlatform.parsed) cpu kernel;
  releasePath = "bin/${cpu.name}/${kernel.name}/release";

  versionInRange =
    v: lo: hi:
    (versionAtLeast v lo) && (v == hi || versionOlder v hi);
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
      freeimage
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
      brokenSamples = [ ];
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

  installPhase = ''
    runHook preInstall

    install -Dm755 -t $out/bin ${releasePath}/*

    runHook postInstall
  '';

  meta = {
    description = "Samples for CUDA Developers which demonstrates features in CUDA Toolkit";
    # CUDA itself is proprietary, but these sample apps are not.
    license = lib.licenses.bsd3;
    platforms = [ "x86_64-linux" ];
    maintainers = with lib.maintainers; [ obsidian-systems-maintenance ] ++ lib.teams.cuda.members;
  };
})
