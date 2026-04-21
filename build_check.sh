
#!/bin/zsh
cd /Users/phil/.openclaw/workspace-feishu/agent-forge/ai_accountant/ios
xcodebuild -workspace Runner.xcworkspace -scheme Runner -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' clean build
