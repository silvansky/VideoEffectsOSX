# Video Effects Maker for OS X 

Tool made as a research of slit-scan photography and rolling shutter effect.

Current implemented effects:

* Slit scan with fixed slit
* Slit scan with moving slit
* Rolling shutter

# Build

Run `pod install` first, then open `Slit-Scan Maker OS X.xcworkspace` in Xcode. Build and run as usual.

# Usage

Select effect type, drag-n-drop video to app window, configure some options (or leave defaults) and push "Start" button"

Supported video file types: `.mov`, `.mp4`, `.m4v`, `.qt`.

Output images and videos are saved to `~/Pictures/Slit-Scan Maker/` (directory is created on app's first run).

Output videos are in `.mov` format.

# Memory consumption note

The rolling-shutter effect use a lot of memory. To reduce memory usage use videos of smaller frame size.

For example, if your video stream is 1920x1080 and you start bottom-to-top rolling shutter effect, app will store in memory 1080 raw images of 1920x1080 size. For left-to-right rolling shutter app will store 1920 images.
