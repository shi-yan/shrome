# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Shrome is an experimental browser built with Metal, ImGui, and CEF3 (Chromium Embedded Framework). It's a sandbox project for learning these technologies, not intended for production use.

## Build System

The project supports multiple build systems:

### CMake (Primary)
```bash
# Build with CMake
mkdir build && cd build
cmake ..
make

# Or use Xcode generator
cmake -G Xcode ..
open shrome.xcodeproj
```

### Bazel (Alternative)
```bash
# Build with Bazel
bazel build //:shrome
```

## Architecture

### Core Components

1. **CEF Integration (mycef.h/mm)**: 
   - `MyApp`: Main CEF application class handling browser process
   - `MyClient`: CEF client implementing render, lifecycle, keyboard, and focus handlers
   - `MyRenderHandler`: Handles offscreen rendering with both CPU and GPU (accelerated) paths
   - Supports both regular buffer rendering and Metal IOSurface shared textures

2. **Metal Rendering (metal_view.h/mm)**:
   - `MainMetalView`: MTKView subclass handling Metal rendering and input events
   - Integrates ImGui for UI overlay
   - Implements NSTextInputClient for IME support
   - Custom orthographic projection matrix for 2D rendering

3. **Metal Shaders (cef.metal)**:
   - Vertex shader for quad rendering
   - Fragment shader for texture sampling
   - Simple pass-through pipeline for CEF browser content

4. **Application Entry (main.mm)**:
   - `ClientApplication`: NSApplication subclass implementing CefAppProtocol
   - Handles CEF-required event routing and termination

### Key Features

- **Offscreen Rendering**: CEF renders to textures that are displayed via Metal
- **Accelerated Rendering**: Uses Metal IOSurface shared textures when available
- **ImGui Integration**: UI overlay system with Metal backend
- **IME Support**: Full input method editor support for international text input
- **Popup Handling**: Browser popup windows rendered as overlays

### Dependencies

- **CEF Binary**: Located in `cef_binary_138.0.26+g84f2d27+chromium-138.0.7204.158_macosarm64/`
- **ImGui**: Fetched from GitHub (docking branch)
- **Metal-CPP**: Fetched from Apple developer site
- **System Frameworks**: Cocoa, Metal, MetalKit, QuartzCore, GameController

### Key Files

- `main.mm`: Application entry point and NSApplication setup
- `mycef.h/mm`: CEF wrapper classes and browser logic
- `metal_view.h/mm`: Metal rendering and input handling
- `cef.metal`: Metal shaders for browser content rendering
- `CMakeLists.txt`: Primary build configuration
- `BUILD.bazel`: Bazel build configuration

### Development Notes

- The project uses C++23 standard
- ARC (Automatic Reference Counting) is enabled for Objective-C code
- Warning-as-error is disabled for compatibility
- External begin frame is enabled for CEF offscreen rendering
- Shared texture support is enabled for Metal acceleration