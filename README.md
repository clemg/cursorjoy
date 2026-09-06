# Credits

This is a native way of doing what [Stefan showcased in his original tweet](https://x.com/heystefan_/status/2095558659283866109)
It was so good that I wanted to have my own, props to him :)

# Cursor Joy

Cursor Joy is a tiny MacOS app that replaces the native pointer with a swinging
one: the arrow tilts with the speed and direction of your mouse and springs back
with a satisfying wobble when you stop. It does this by hiding the native cursor
via private CoreGraphics APIs and redrawing a vector pointer in an always-on-top,
click-through overlay window that tracks the mouse, running the simulation.

# Demo

<video src="https://github.com/user-attachments/assets/871cb341-95b7-49d0-ba9c-9c6362909fcf" controls muted width="100%"></video>
