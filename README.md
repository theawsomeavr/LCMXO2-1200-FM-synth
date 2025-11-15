An FM synth similar to the DX7 (with 6 operators per voice and 16 voices)
based on the Lattice LCMXO2-1200HC FPGA (aka tinyfpga).

# TODO
place images in this thingy

Dependecies:

Lattice Diamond (3.14.0.75.2).

GDC (GNU D compiler).

openFPGALoader (https://github.com/trabucayre/openFPGALoader).

A jtag programmer (dirtyjtag using an stm32f103 https://github.com/dirtyjtag/DirtyJTAG).

Building:
This project uses a tiny d program (flaya.d) to run the Lattice tools in order
to create the bit file and flash, the concept is heavily inspired by tsoding's
nob.h build system (https://github.com/tsoding/nob.h).

Simply bootstrap flaya.d using gdc and run flaya, any modifications after the
bootstrap to flaya.d will trigger a recompilation so it acts as an 'scripting'
language
```bash
gdc -o flaya flaya.d
./flaya
```
