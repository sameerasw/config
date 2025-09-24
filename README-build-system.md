# Universal macOS Build Script

A flexible, configurable build script for macOS applications that handles DMG creation, code signing, notarization, and Sparkle appcast generation.

## Features

- ✅ **Configurable**: Use simple config files instead of modifying scripts
- ✅ **Modular**: Choose which build steps to run
- ✅ **Secure**: Credentials stored in macOS Keychain
- ✅ **Auto-detection**: Automatically finds Sparkle framework
- ✅ **Progress tracking**: Visual progress indication
- ✅ **Error handling**: Robust error checking and reporting

## Quick Start

1. **Copy the template config file:**

   ```bash
   cp template.build.config myapp.build.config
   ```

2. **Edit the config file** with your project details

3. **Store credentials in Keychain:**

   ```bash
   # Store your Apple ID
   security add-generic-password -s "MyAppAppleID" -a "$(whoami)" -w "your-apple-id@example.com"

   # Store your app-specific password
   security add-generic-password -s "MyAppAppPassword" -a "$(whoami)" -w "your-app-specific-password"
   ```

4. **Run the build:**
   ```bash
   ./build-mac.sh myapp.build.config
   ```

## Usage

```bash
./build-mac.sh [config_file] [-y|--yes] [-h|--help]
```

### Options

- `config_file`: Path to your configuration file (default: `template.build.config`)
- `-y, --yes`: Skip confirmation prompts
- `-h, --help`: Show help message

### Examples

```bash
# Build with default config
./build-mac.sh

# Build with custom config
./build-mac.sh airsync.build.config

# Build without confirmations
./build-mac.sh myapp.build.config -y
```

## Configuration File Format

Configuration files use a simple `key=value` format:

```ini
# Comments start with #
project_name=MyApp
project_dir=/path/to/project
output_dir=/path/to/output
steps=Cleanup updates directory,Build DMG,Notarize DMG
```

### Required Configuration

| Key            | Description                         | Example                     |
| -------------- | ----------------------------------- | --------------------------- |
| `project_name` | Name of your application            | `AirSync`                   |
| `project_dir`  | Path to your Xcode project          | `/Users/dev/MyApp`          |
| `output_dir`   | Where to place build artifacts      | `/Users/dev/MyApp/releases` |
| `steps`        | Comma-separated list of build steps | `Build DMG,Notarize DMG`    |

### Optional Configuration

| Key                 | Description               | Default                   |
| ------------------- | ------------------------- | ------------------------- |
| `skip_confirmation` | Skip confirmation prompts | `false`                   |
| `dmg_name`          | Name of the DMG file      | `{project_name}.dmg`      |
| `background_image`  | DMG background image path | None                      |
| `developer_id`      | Code signing identity     | Required for notarization |
| `team_id`           | Apple Developer Team ID   | Required for notarization |
| `dmg_window_size`   | DMG window dimensions     | `600,400`                 |
| `dmg_icon_size`     | DMG icon size             | `128`                     |
| `sparkle_dir`       | Path to Sparkle framework | Auto-detected             |

### Keychain Configuration

| Key                             | Description                            |
| ------------------------------- | -------------------------------------- |
| `apple_id_keychain_service`     | Keychain service name for Apple ID     |
| `app_password_keychain_service` | Keychain service name for app password |

## Available Build Steps

1. **Cleanup updates directory** - Removes old build artifacts
2. **Build DMG** - Creates a DMG installer package
3. **Notarize DMG** - Submits DMG for Apple notarization
4. **Staple & Validate DMG** - Staples notarization ticket
5. **Generate Sparkle Appcast** - Creates Sparkle update feed

## Setting Up Keychain Credentials

Store your Apple ID and app-specific password securely in Keychain:

```bash
# Add Apple ID
security add-generic-password -s "YourAppAppleID" -a "$(whoami)" -w "your-apple-id@example.com"

# Add app-specific password
security add-generic-password -s "YourAppAppPassword" -a "$(whoami)" -w "abcd-efgh-ijkl-mnop"
```

Then reference these in your config file:

```ini
apple_id_keychain_service=YourAppAppleID
app_password_keychain_service=YourAppAppPassword
```

## Prerequisites

- Xcode and Xcode Command Line Tools
- [create-dmg](https://github.com/andreyvit/create-dmg): `brew install create-dmg`
- Valid Apple Developer account with notarization capabilities
- App-specific password for notarization

## Troubleshooting

### Common Issues

1. **"create-dmg command not found"**

   ```bash
   brew install create-dmg
   ```

2. **"Sparkle directory not found"**

   - Ensure Sparkle is added to your Xcode project
   - Or specify `sparkle_dir` in your config file

3. **"Notarization failed"**

   - Verify your Apple ID and app-specific password
   - Check your team ID is correct
   - Ensure your app is properly code signed

4. **"Config file not found"**
   - Use absolute paths or ensure the config file is in the same directory as the script

### Debug Mode

Add `set -x` to the script for detailed execution logging.

## Example Configurations

See the included example config files:

- `airsync.build.config` - AirSync project configuration
- `mytexteditor.build.config` - Example for a different app
- `template.build.config` - Template for new projects

## License

This script is provided as-is for educational and development purposes.
