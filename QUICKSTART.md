# Quick start

Build mmx Studio on the OS you want to run it on: Linux, macOS, or Windows.
The start script handles dependencies and launches the desktop app.

## 1. Install the tools

Install Git, [Flutter **3.47.9**](https://docs.flutter.dev/install/archive),
[Python **3.9+**](https://www.python.org/downloads/), and
[Rust through rustup](https://rustup.rs/). Put Flutter, Python, and Cargo on
your `PATH`, then open a new terminal. Flutter includes Dart; use that SDK.

Install the pinned Rust toolchain:

```sh
rustup toolchain install 1.99.1 --profile minimal --component rustfmt --component clippy
```

Complete the setup for your OS:

### Linux

On Ubuntu 24.04, install the native build tools and Vulkan runtime:

```sh
sudo apt-get update
sudo apt-get install -y clang cmake ninja-build pkg-config libgtk-3-dev libstdc++-12-dev liblzma-dev libvulkan1 mesa-vulkan-drivers
```

Use equivalent packages on other distributions. See Flutter's
[Linux setup](https://docs.flutter.dev/platform-integration/linux/setup).
Run Studio in a graphical desktop session.

### macOS

Install Xcode, finish its first-launch setup, and install CocoaPods as described
in Flutter's [macOS setup](https://docs.flutter.dev/platform-integration/macos/setup).
Add both Rust targets for the native renderer's universal build:

```sh
rustup target add --toolchain 1.99.1 aarch64-apple-darwin x86_64-apple-darwin
```

### Windows

Install Visual Studio with the **Desktop development with C++** workload,
including its Windows SDK and CMake tools. Use Rust's MSVC toolchain. See
Flutter's [Windows setup](https://docs.flutter.dev/platform-integration/windows/setup).
Run the commands below in PowerShell. Python must be on `PATH` for the native build.

Check your setup:

```sh
flutter doctor -v
flutter devices
```

Resolve problems for your desktop platform. Android and iOS tooling are not
needed to build Studio.

## 2. Clone and start

```sh
git clone https://github.com/palindsay/mmx.git
cd mmx
```

Linux or macOS:

```sh
python3 start.py
```

Windows:

```powershell
py -3 start.py
```

The script detects your OS, fetches Dart dependencies, and builds and runs
Studio in release mode. The native renderer builds automatically. The first
build downloads dependencies and takes longer; later builds reuse the cache.
Close the app or press `q` in the Flutter terminal to quit.

Studio starts with a sphere. Import a model using the toolbar, choose its units,
and try a tool. Save an editable scene as `.mmx`; export a mesh when you need
OBJ, STL, 3MF, or another supported interchange format.

## Development and build-only options

```sh
python3 start.py --debug       # Run with hot reload; press r after editing
python3 start.py --build-only  # Build release files without opening Studio
python3 start.py --help
```

On Windows, replace `python3` with `py -3`. The script also works when called
by its path from another directory.

Build outputs are under `apps/mmx_studio/`:

| Platform | Release output |
|---|---|
| Linux | `build/linux/<architecture>/release/bundle/` |
| macOS | `build/macos/Build/Products/Release/mmx_studio.app` |
| Windows | `build/windows/x64/runner/Release/` |

Keep the whole bundle together, including libraries and data. These are local
builds; [packaging and signing](docs/RELEASE.md) are separate steps.

To run the same steps manually, from the repository root:

```sh
cd apps/mmx_studio
flutter pub get
flutter run -d linux --release  # Replace linux with macos or windows
```

## CLI only

The geometry CLI needs Dart; it does not build the desktop renderer.
From the repository root:

```sh
cd packages/mmx_core
dart pub get
dart run bin/mmx.dart info test/fixtures/models/sphere.obj
dart run bin/mmx.dart --help
```

See the [CLI reference](docs/CLI.md) for editing and conversion commands.

## If it does not start

- **Command not found:** check `PATH`, reopen the terminal, and rerun
  `flutter doctor -v`.
- **Desktop device missing:** run `flutter config --enable-linux-desktop`,
  `--enable-macos-desktop`, or `--enable-windows-desktop` for your OS, then
  rerun `flutter devices`.
- **Native build fails:** check the Rust version, Python, and your platform's
  compiler setup. On macOS, check both Rust targets above.
- **Rendering is slow:** check Studio's renderer status and try its CPU option.
  A software Vulkan/DX12 adapter can be slower than the CPU renderer.

Ready to change the code? Read [CONTRIBUTING.md](CONTRIBUTING.md).
