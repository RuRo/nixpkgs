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
  cuda_profiler_api,
  libcublas,
  libcufft,
  libcurand,
  libcusolver,
  libcusparse,
  libnpp,
  libnvjitlink,
  libnvjpeg,

  # Normal dependencies
  freeimage,
  glfw3,
}:
let
  inherit (lib) optionals versionAtLeast versionOlder;

  inherit (backendStdenv.hostPlatform.parsed) cpu kernel;
  releasePath = "bin/${cpu.name}/${kernel.name}/release";
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

      # CUDA dependencies
      cuda_cudart
      cuda_nvcc
      cuda_nvrtc
      cuda_profiler_api
      libcublas
      libcufft
      libcurand
      libcusolver
      libcusparse
      libnpp
      libnvjitlink
      libnvjpeg
      cuda_cudart.static
      libcublas.static
      libcufft.static
      libcurand.static
      libcusparse.static
    ]
    ++ optionals (versionAtLeast finalAttrs.version "11.4") [
      cuda_cccl
    ];

  # See https://github.com/NVIDIA/cuda-samples/issues/75.
  patches = optionals (finalAttrs.version == "11.3") [
    (fetchpatch {
      url = "https://github.com/NVIDIA/cuda-samples/commit/5c3ec60faeb7a3c4ad9372c99114d7bb922fda8d.patch";
      hash = "sha256-0XxdmNK9MPpHwv8+qECJTvXGlFxc+fIbta4ynYprfpU=";
    })
  ];

  enableParallelBuilding = true;

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
