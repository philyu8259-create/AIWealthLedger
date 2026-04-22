
#!/bin/zsh

set -euo pipefail

repo_root="$(cd "$(dirname "$0")" && pwd)"
cd "$repo_root/ios"

xcodebuild \
  -workspace Runner.xcworkspace \
  -scheme Runner \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  clean build
