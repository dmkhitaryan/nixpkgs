{
  stdenv,
  lib,
  fetchFromGitHub,
  fetchpatch,
  cmake,
  imagemagick,
  libicns,
  kdePackages,
  grim,
  makeBinaryWrapper,
  kdsingleapplication,
  nix-update-script,
  enableWlrSupport ? false,
  enableMonochromeIcon ? false,
}:

assert stdenv.hostPlatform.isDarwin -> (!enableWlrSupport);
stdenv.mkDerivation (finalAttrs: {
  pname = "flameshot";
  # wlr screenshotting is currently only available on unstable version (>12.1.0)
  version = "13.0.0";

  src = fetchFromGitHub {
    owner = "flameshot-org";
    repo = "flameshot";
    tag = "v${finalAttrs.version}";
    hash = "sha256-famx633wdeFVtQCg5L3JsdMLBdowYTEWNRD6hd+pMhw=";
  };

  cmakeFlags = [
    "-DCMAKE_CXX_FLAGS=-I${kdsingleapplication}/include/kdsingleapplication-qt6"
    "-DCMAKE_EXE_LINKER_FLAGS=-L${kdsingleapplication}/lib"
    (lib.cmakeFeature "KDSingleApplication_DIR" "${kdsingleapplication}/lib/cmake/KDSingleApplication-qt6")
    (lib.cmakeBool "DISABLE_UPDATE_CHECKER" true)
    (lib.cmakeBool "USE_MONOCHROME_ICON" enableMonochromeIcon)
  ]
  ++ lib.optionals stdenv.hostPlatform.isLinux [
    (lib.cmakeBool "USE_WAYLAND_CLIPBOARD" true)
    (lib.cmakeBool "USE_WAYLAND_GRIM" enableWlrSupport)
  ]
  ++ lib.optionals stdenv.hostPlatform.isDarwin [
    (lib.cmakeFeature "Qt6_DIR" "${kdePackages.qtbase.dev}/lib/cmake/Qt6")
  ];

  # 1. Prevents the package from attempting to fetch libraries through the internet.
  # 2. Package expects "kdsingleapplication", in Nixpkgs: "kdsingleapplication-qt6".
  patches = [
    ./qt-color-widgets.patch
    ./kds-lib-link.patch
  ];

  nativeBuildInputs = [
    cmake
    kdePackages.qttools
    kdePackages.qtsvg
    kdePackages.wrapQtAppsHook
    makeBinaryWrapper
  ]
  ++ lib.optionals stdenv.hostPlatform.isDarwin [
    imagemagick
    libicns
  ];

  buildInputs = [
    kdsingleapplication
    kdePackages.qt-color-widgets
    kdePackages.qtbase
    kdePackages.kguiaddons
  ];

  postPatch = lib.optionalString stdenv.hostPlatform.isDarwin ''
    # Fix icns generation running concurrently with png generation
    sed -E -i '/"iconutil -o/i\
        )\
        execute_process(\
    ' src/CMakeLists.txt

    # Replace unavailable commands
    sed -E -i \
        -e 's/"sips -z ([0-9]+) ([0-9]+) +(.+) --out /"magick \3 -resize \1x\2\! /' \
        -e 's/"iconutil -o (.+) -c icns (.+)"/"png2icns \1 \2\/*{16,32,128,256,512}.png"/' \
        src/CMakeLists.txt
  '';

  postInstall = lib.optionalString stdenv.hostPlatform.isDarwin ''
    mkdir $out/Applications
    mv $out/bin/flameshot.app $out/Applications

    ln -s $out/Applications/flameshot.app/Contents/MacOS/flameshot $out/bin/flameshot

    rm -r $out/share/applications
    rm -r $out/share/dbus*
    rm -r $out/share/icons
    rm -r $out/share/metainfo
  '';

  dontWrapQtApps = true;

  postFixup =
    let
      binary =
        if stdenv.hostPlatform.isDarwin then
          "Applications/flameshot.app/Contents/MacOS/flameshot"
        else
          "bin/flameshot";
    in
    ''
      wrapProgram $out/${binary} \
        ${lib.optionalString enableWlrSupport "--prefix PATH : ${lib.makeBinPath [ grim ]}"} \
        ''${qtWrapperArgs[@]}
    '';

  passthru = {
    updateScript = nix-update-script { extraArgs = [ "--version=branch" ]; };
  };

  meta = {
    description = "Powerful yet simple to use screenshot software";
    homepage = "https://github.com/flameshot-org/flameshot";
    changelog = "https://github.com/flameshot-org/flameshot/releases";
    mainProgram = "flameshot";
    maintainers = with lib.maintainers; [
      scode
      oxalica
    ];
    license = lib.licenses.gpl3Plus;
    platforms = lib.platforms.linux ++ lib.platforms.darwin;
  };
})
