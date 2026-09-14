#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

bash -n nexus-linux-setup.sh

# Machine-specific values from the original reproduction must never leak into
# reusable automation.
if grep -R -nE 'N4gsrqVepcjt|/home/motto|DP-5|pgrep -u 1000' --exclude-dir=.git --exclude=static.sh .; then
  echo "hard-coded reproduction identity found" >&2
  exit 1
fi

# The generated direct kiosk must remain on localhost because Chrome app class
# matching depends on the host name.
grep -q 'http://localhost:9400/panel/' nexus-linux-setup.sh

# The helper must not write raw PWM values.
if grep -nE '>[[:space:]]*/sys/class/hwmon/.*/pwm|tee[[:space:]].*/sys/class/hwmon/.*/pwm' nexus-linux-setup.sh; then
  echo "raw PWM write detected" >&2
  exit 1
fi

echo "static checks passed"
