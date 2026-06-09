#!/bin/zsh
# Reset TCC grants for the app when ad-hoc re-signing wedges the prompts.
BUNDLE_ID=com.maxtyroler.CommandShiftHero
tccutil reset AppleEvents "$BUNDLE_ID" || true
tccutil reset MediaLibrary "$BUNDLE_ID" || true
tccutil reset All "$BUNDLE_ID" || true
echo "TCC reset for $BUNDLE_ID — next launch will re-prompt."
