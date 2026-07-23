# Syybott's Media Optimizer

## What It Does
A Windows application designed to optimize supported image and video files, reducing their storage footprint while attempting to maintain acceptable quality

It operates in four major modes:
- **Copy Mode**: Optimizes media from a source folder and places the results into a separate destination folder
- **Modify Mode**: Optimizes media directly in the chosen folder, replacing the original files in-place when a smaller optimized version is successfully generated
- **Image Test**: Generates test optimizations for a single image to help you evaluate quality and savings
- **Video Test**: Generates test optimizations for a single video to help you evaluate playback and quality

## Before You Start
**WARNING**: Modify Mode operates in-place and **will permanently delete or replace your original files** if an optimization is successful

Always back up your important media libraries to a separate drive or location before running Modify Mode

## Basic Use
1. Open the application
2. Choose the folder containing your media
3. Choose image or video processing from the main interface
4. Use Test Mode first when desired to preview the results
5. Review the generated test outputs to ensure the quality meets your needs
6. Run the full operation.

## Test Modes
- A test run processes one eligible source file at a time
- Repeated test runs automatically continue to the next untested source file
- Generated test outputs are explicitly excluded from being reused as source files in future operations
- The application will report when no untested files remain in the selected folder

## Important
Keep the entire release folder together. The application relies on external required tools (such as FFmpeg and cwebp) which may be downloaded and stored directly beside the application executable. Moving the application without these tools will require them to be downloaded again.
