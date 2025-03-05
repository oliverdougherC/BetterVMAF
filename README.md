# Better VMAF

A native macOS application for calculating VMAF (Video Multi-Method Assessment Fusion) scores between two videos.

## Features

- Native macOS interface
- Real-time VMAF calculation
- Detailed metrics including:
  - VMAF score
  - Score range (min/max)
  - Harmonic mean
- Support for common video containers and codecs

## System Requirements

- macOS 13.0 or later
- FFmpeg with libvmaf support (included in the app bundle)

## Installation

1. Download the latest release from the [Releases](https://github.com/oliverdougherC/BetterVMAF/releases) page
2. Open the downloaded `Better_VMAF.dmg` file
3. Drag the "Better VMAF" app to your Applications folder
4. The first time you run the app, you'll need to:
   - Right-click (or Control-click) the app in your Applications folder
   - Select "Open" from the context menu
   - Click "Open" in the security dialog that appears

This is necessary because the app is not signed with an Apple Developer ID. You only need to do this once.

## Development Setup

1. Clone the repository:
   ```bash
   git clone https://github.com/oliverdougherC/BetterVMAF
   cd BetterVMAF
   ```

2. Open the project in Xcode:
   ```bash
   open VMAF.xcodeproj
   ```

3. Build and run the project in Xcode

## Building for Distribution

To create a DMG for distribution:

1. Open Terminal and navigate to the project directory
2. Run the build script:
   ```bash
   ./create_dmg.sh
   ```
3. The script will create `Better-VMAF.dmg` in the project directory

## How It Works

Better VMAF uses FFmpeg with the libvmaf library to calculate video quality metrics. The app provides a simple interface for:
1. Selecting a reference video (original/high quality)
2. Selecting a comparison video (to be evaluated)
3. Calculating and displaying VMAF scores

The VMAF score ranges from 0 to 100, where:
- 100 represents perfect quality
- Scores above 93 indicate excellent quality
- Scores below 60 indicate significant quality issues

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- [FFmpeg](https://ffmpeg.org/) for video processing
- [libvmaf](https://github.com/Netflix/vmaf) for VMAF calculation
- Apple's SwiftUI framework for the user interface 