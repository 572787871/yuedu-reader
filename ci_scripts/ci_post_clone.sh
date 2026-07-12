#!/bin/sh

#  ci_post_clone.sh
#  Yuedu-Reader
#
#  Firebase was removed from this project, so there is no GoogleService-Info.plist
#  to decode. This script is a no-op now and exists only to keep Xcode Cloud
#  environments happy if they still run it.

set -e

echo "=== Running ci_post_clone.sh ==="
echo "Firebase/GoogleSignIn integration has been removed; skipping plist decode."
echo "=== ci_post_clone.sh completed ==="
