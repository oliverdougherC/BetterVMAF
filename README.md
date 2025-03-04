# VMAF Calculator

A macOS application for calculating Video Multi-Method Assessment Fusion (VMAF) scores between two video files. This tool provides an intuitive interface for comparing video quality using Netflix's VMAF algorithm.

## Features

- Simple drag-and-drop interface for selecting reference and comparison videos
- Real-time VMAF score calculation
- Displays comprehensive metrics including:
  - VMAF Score
  - Score Range (min/max)
  - Harmonic Mean
- Built-in FFmpeg with libvmaf support
- Native macOS application

## Requirements

- macOS 13.0 or later
- Xcode 15.0 or later (for development)
- FFmpeg with libvmaf support (bundled with the application)

## Installation

1. Download the latest release from the releases page
2. Drag the VMAF.app to your Applications folder
3. Launch the application

## Development Setup

1. Clone the repository:
   ```bash
   git clone https://github.com/oliverdougherC/VMAF
   ```

2. Open the project in Xcode:
   ```bash
   cd VMAF
   open VMAF.xcodeproj
   ```

3. Build and run the project in Xcode

## Usage

1. Launch VMAF Calculator
2. Click "Select" next to "Reference Video" to choose your original video
3. Click "Select" next to "Comparison Video" to choose the video you want to compare
4. Click "Calculate VMAF" to start the analysis
5. Wait for the calculation to complete
6. View the results showing the VMAF score and related metrics

## Technical Details

The application uses FFmpeg with libvmaf to calculate VMAF scores. The calculation process:
1. Loads both videos using FFmpeg
2. Processes them frame by frame
3. Calculates VMAF metrics using the libvmaf library
4. Outputs results in JSON format
5. Parses and displays the results in the UI

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Acknowledgments

- [Netflix VMAF](https://github.com/Netflix/vmaf) - The VMAF algorithm
- [FFmpeg](https://ffmpeg.org/) - Video processing framework
- [libvmaf](https://github.com/Netflix/vmaf/tree/master/libvmaf) - VMAF implementation library 