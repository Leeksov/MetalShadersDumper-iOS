# MetalShadersDumper-iOS

MetalShadersDumper-iOS is an iOS tweak that hooks into the runtime Metal shader compilation process, logs the shader source code, and saves each shader into a separate file inside the `Documents/MetalShadersDumped` folder.

---

## Features

- Hooks the `newLibraryWithSource:options:error:` method of the Metal device.
- Logs shader source code to the system log.
- Saves each shader into a separate file with sequential names (`shader_001.metal`, `shader_002.metal`, etc.).
- Automatically creates the folder for storing shaders if it does not exist.

---

## Installation and Usage

1. Build the tweak using Theos.
2. Install the tweak on a jailbroken device with Cydia Substrate.
3. Launch the target app/game that uses Metal.
4. Each time the app compiles a shader from source, the shader source will be saved to a file and logged.

---

## Location of Saved Files

Shader files are saved to: /var/mobile/Containers/Data/Application/<App_UUID>/Documents/MetalShadersDumped/

