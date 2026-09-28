`WindowSpaceMove.c`, `WindowSpaceMove.h`, and `LICENSE.WhichSpace` are vendored
unchanged from [gechr/WhichSpace](https://github.com/gechr/WhichSpace/tree/d894247d141a576396144bc60d48576a7d60b69b/WhichSpace/Classes),
revision `d894247d141a576396144bc60d48576a7d60b69b` (MIT, George Christou).

`main.m` is our small command-line adapter: exact window ID + target Space ID,
with membership confirmation before success. It uses the bridged backend only.
It never activates applications, switches desktops, or simulates mouse dragging.
Build with `make` from the Spoon directory. The generated binary is not tracked.
