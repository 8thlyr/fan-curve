# Rendered to docs/demo.gif by `vhs docs/demo.tape` from the repo root, after
# `sh docs/demo-setup.sh` has built fan-curve-curve into /tmp/fan-curve-demo.
#
# This records `fan-curve-curve`, the curve engine on the command line, because the menu-bar
# app itself needs a Mac with real fans to show anything true. The numbers are the app's own
# FanCurveCore code: the same interpolation, the same scene ceiling, the same fan RPM mapping,
# so this is what the app asks the fans for at each temperature.
Output docs/demo.gif
Set Shell "bash"
Set FontSize 15
Set Width 1000
Set Height 620
Set Padding 14
Set TypingSpeed 28ms

Hide
Type "cd /tmp/fan-curve-demo && export PATH=/tmp/fan-curve-demo:$PATH"
Enter
Sleep 600ms
Show

Type "# the built-in curve, every 10 degrees:"
Enter
Sleep 500ms
Type "fan-curve-curve --step 10"
Enter
Sleep 1800ms

Type "# a steeper curve of my own:"
Enter
Sleep 500ms
Type "fan-curve-curve --points 40:10,60:50,80:90 --step 10"
Enter
Sleep 1800ms

Type "# Quiet scene: the ceiling caps the curve, and drops to it at once:"
Enter
Sleep 500ms
Type "fan-curve-curve --points 40:10,60:50,80:90 --ceiling 45 --step 20"
Enter
Sleep 2000ms

Type "# an invalid curve is refused rather than guessed at:"
Enter
Sleep 500ms
Type "fan-curve-curve --points 40:80,60:20"
Enter
Sleep 1800ms
