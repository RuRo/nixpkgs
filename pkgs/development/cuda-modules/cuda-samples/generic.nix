{
  autoAddDriverRunpath,
  backendStdenv,
  cudaVersion,
  fetchFromGitHub,
  fetchpatch,
  hash,
  lib,
  symlinkJoin,

  # CUDA dependencies
  cuda_cccl,
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
  cmake,
  pkg-config,
  util-linux,
  which,

  # Graphical dependencies
  glfw3,
  libGL,
  libGLU,
  libglut,
  xorg,

  # Optional dependencies
  withFreeimage ? false, # default to false, because freeimage is insecure
  freeimage,

  withMPI ? true,
  mpi,

  withVulkan ? true,
  vulkan-headers,
  vulkan-loader,
}:
let
  inherit (lib)
    concatMapStrings
    optionals
    versionAtLeast
    versionOlder
    ;

  inherit (backendStdenv.hostPlatform.parsed) cpu kernel;
  releasePath = "bin/${cpu.name}/${kernel.name}/release";

  versionInRange =
    v: lo: hi:
    (versionAtLeast v lo) && (versionAtLeast hi v);
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
      which
    ]
    ++ optionals withMPI [ mpi.dev ]
    # CMake has to run as a native, build-time dependency for libNVVM samples.
    # However, it's not the primary build tool -- that's still make.
    # As such, we disable CMake's build system.
    ++ optionals (versionAtLeast finalAttrs.version "12.2") [ cmake ];

  dontUseCmakeConfigure = true;

  buildInputs =
    [
      glfw3
      libGL
      libGLU
      libglut
      xorg.libX11
    ]
    ++ optionals withFreeimage [ freeimage ]
    ++ optionals withVulkan [
      vulkan-headers
      vulkan-loader
    ]
    # CUDA dependencies
    ++ [
      cuda_cccl
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
    ++ optionals (versionAtLeast finalAttrs.version "11.8") [ cuda_profiler_api ]
    ++ optionals (versionAtLeast finalAttrs.version "12.0") [ libnvjitlink ];

  patches =
    optionals (finalAttrs.version == "11.3") [
      # See https://github.com/NVIDIA/cuda-samples/issues/75.
      # No rule to make target '../../common/src/helper_multiprocess.cpp'
      (fetchpatch {
        url = "https://github.com/NVIDIA/cuda-samples/commit/5c3ec60faeb7a3c4ad9372c99114d7bb922fda8d.patch";
        hash = "sha256-0XxdmNK9MPpHwv8+qECJTvXGlFxc+fIbta4ynYprfpU=";
      })
    ]
    ++ optionals (versionInRange finalAttrs.version "11.6" "12.1") [
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
        # ======== Broken without optional dependencies ========
        optionals (!withFreeimage) [
          # The following samples require FreeImage.
          "FilterBorderControlNPP" # FreeImage is not set up correctly.
          "boxFilterNPP" # FreeImage is not set up correctly.
          "cannyEdgeDetectorNPP" # FreeImage is not set up correctly.
          "freeImageInteropNPP" # FreeImage is not set up correctly.
          "histEqualizationNPP" # FreeImage is not set up correctly.
        ]
        ++ optionals (!withMPI) [
          # The following samples require MPI.
          "simpleMPI" # No MPI compiler found.
        ]
        ++ optionals (!withVulkan) [
          # The following samples require Vulkan.
          "simpleVulkan" # libvulkan.so not found, please install Vulkan SDK
          "simpleVulkanMMAP" # libvulkan.so not found, please install Vulkan SDK
          "vulkanImageCUDA" # libvulkan.so not found, please install Vulkan SDK
        ]

        # ======== Broken on unsupported platforms ========
        ++ optionals (backendStdenv.hostPlatform.system == "x86_64-linux") [
          # The following samples require DriveOS-specific libraries like
          # NvSciBuf and NvSciSync that are not available on linux
          "cudaNvSci" # libnvscibuf.so not found, please install libnvscibuf.so
          "cudaNvSciNvMedia" # is not supported on Linux x86_64

          # The following samples require the cuDLA library,
          # which is only available on aarch64-jetson
          "cuDLAErrorReporting" # is not supported on Linux x86_64
          "cuDLAHybridMode" # is not supported on Linux x86_64
          "cuDLALayerwiseStatsHybrid" # is not supported on Linux x86_64
          "cuDLALayerwiseStatsStandalone" # is not supported on Linux x86_64
          "cuDLAStandaloneMode" # is not supported on Linux x86_64

          # The following samples require the D3D{9,10,11,12} libraries,
          # which are only available on Windows
          "SLID3D10Texture" # is not supported on Linux
          "VFlockingD3D10" # is not supported on Linux
          "fluidsD3D9" # is not supported on Linux
          "simpleD3D10" # is not supported on Linux
          "simpleD3D10RenderTarget" # is not supported on Linux
          "simpleD3D10Texture" # is not supported on Linux
          "simpleD3D11" # is not supported on Linux
          "simpleD3D11Texture" # is not supported on Linux
          "simpleD3D12" # is not supported on Linux
          "simpleD3D9" # is not supported on Linux
          "simpleD3D9Texture" # is not supported on Linux

          # The following samples require the GLES/EGL libraries.
          # For some reason cuda-samples claims that they are NOT available on
          # x86_64-linux. Perhaps, these samples use some platform-specific
          # subset of GLES/EGL ¯\_(ツ)_/¯.
          "EGLSync_CUDAEvent_Interop" # is not supported on Linux x86_64
          "fluidsGLES" # is not supported on Linux x86_64
          "nbody_opengles" # is not supported on Linux x86_64
          "nbody_screen" # is not supported on Linux x86_64
          "simpleGLES" # is not supported on Linux x86_64
          "simpleGLES_EGLOutput" # is not supported on Linux x86_64
          "simpleGLES_screen" # is not supported on Linux x86_64
        ]

        # ======== Broken due to version incompatibilities ========
        ++ optionals (versionOlder "2.33" backendStdenv.cc.libc.version) [
          "cuHook" # GLIBC > 2.33 is not supported
        ]
        ++ optionals (versionInRange finalAttrs.version "12.0" "12.1") [
          # The include/cuda/std/barrier header provided by cuda_cccl.dev seems
          # to be incompatible with newer versions of GCC according to this post
          # https://forums.developer.nvidia.com/t/cuda-12-1-error-when-building-cuda-samples/246465
          # FIXME: This is probably happening, because CUDA 12.0 and 12.1
          #        officially support GCC up to versions 12.1 and 12.2, but
          #        pkgs/development/cuda-modules/nvcc-compatibilities.nix
          #        only allows specifying the maximum *major* version of GCC.
          #        As a consequence, CUDA 12.0 and 12.1 are currently using
          #        GCC 12.4.0 which is technically out of spec.
          "bf16TensorCoreGemm" # function "operator new" cannot be called with the given argument list
          "dmmaTensorCoreGemm" # function "operator new" cannot be called with the given argument list
          "dmmaTensorCoreGemm" # function "operator new" cannot be called with the given argument list
          "globalToShmemAsyncCopy" # function "operator new" cannot be called with the given argument list
          "simpleAWBarrier" # function "operator new" cannot be called with the given argument list
          "tf32TensorCoreGemm" # function "operator new" cannot be called with the given argument list
        ]
        ++ optionals (versionOlder finalAttrs.version "11.8") [
          # cuda_profiler_api is required for the following samples
          # but cuda_profiler_api is only available since CUDA 11.8
          "asyncAPI" # cuda_profiler_api.h: No such file or director
          "matrixMul" # cuda_profiler_api.h: No such file or directory
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

  installPhase = ''
    runHook preInstall

    # Install the data files (if any)
    (cd data; find -type f -exec install -vDm 644 {} $out/data/{} \;)

    # Install the compiled executable binaries
    (cd ${releasePath}; find -type f -exec  install -vDm 755 {} $out/bin/{} \;)

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
