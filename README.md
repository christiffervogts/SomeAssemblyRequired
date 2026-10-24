# SAR: Some Assembly Required
 
> **under construction.** The everything is still in its early stages. the design is constantly improving!
 
SAR is a low-cost, open-source 3D printer I have been building from scratch since March 2025. The goal is a much cheaper printer than what is on the market, because most printers are (in my opinion) overpriced or not made well for the price. This machine is a **SCARA-style arm** rather than a Cartesian gantry, which as far as I know is not a common printer design.

## How the arm is controlled

The arm is driven by NEMA 17 stepper motors with TMC2209 drivers, controlled by an ESP32. The ESP32 only reads `.NNGCC` files (New New G-Code Chris), a binary format. The slicer, SARlicer, does all the inverse kinematics ahead of time and writes out every move the arm needs, so the ESP32 never calculates arm geometry. It just reads the instructions and steps the motors.

Each instruction is 3 bytes:

| Byte | Meaning |
|---|---|
| 1 | Axis letter in ASCII. **Capital = clockwise**, **lowercase = counter-clockwise** |
| 2-3 | Number of 1/16th steps, as a 16-bit unsigned integer (0 to 65,535) |

Example (hex):

    41 00 64   61 00 64

This means "move A clockwise by 100 1/16th steps, then move A counter-clockwise by 100 1/16th steps." The first instruction in bits is `01000001 00000000 01100100`.
## Repository layout
 
```
SomeAssemblyRequired/
├── README.md
└── SARlicer/
    ├── main.f90        slicer entry point (Fortran 90)
    ├── stl2ascii.c     binary STL -> ASCII STL converter (C)
    ├── Benchy.stl      test model (binary STL, 225,706 triangles)
    ├── Test.stl        test model (ASCII STL, a single triangle)
    ├── converted.stl   ASCII version of Benchy.stl (generated)
    └── segments.txt    sample 2D line segments (x1 y1 x2 y2), 729 lines
├──CAD/
    |── SolidWorksOriginalParts/
    |── StepFormatedParts/
    |── DesignDrawlingsAndOtherDocs/
    └── STLs/
```
 
## SARlicer: current state
 
SARlicer takes an STL file as input. It is early-stage. Right now it does the following:
 
- Prompts for the STL path, a print quality value, and the nozzle diameter.
- Sets layer height to 0.8 x nozzle diameter.
- Detects whether the STL is binary or ASCII by checking the file size against the triangle count in the header.
- If binary, runs `./stl2ascii` to write `converted.stl`, then reads that file.
- Reads every `vertex` line and prints its x, y, z.
**Not yet implemented:** actual layer slicing, perimeters and infill, G-code output, and passing the toolpath through the angle lookup. The quality and layer height values are collected but not used yet. `segments.txt` is sample output from a slicing experiment and is not written by the current `main.f90`.
 
### Build and run
 
Requires `gcc` and `gfortran`.
 
```bash
cd SARlicer
gcc -O2 stl2ascii.c -o stl2ascii
gfortran main.f90 -o SARlicerMain
./SARlicerMain
```
 
`stl2ascii` has to be in the same folder you run from. Test input: `Test.stl` (instant) or `Benchy.stl` (about 677,000 vertices printed).
 
## Planned
 
- Bill of materials.
- Drawings and assembly drawings (TODO: add DWG/PNG files).
- Clean this repo up :(

## Why this design?
 
- **Open source.** No proprietary software, easy to modify and repair.
- **Cheap.** The entire reason I created this design is because it should be a cheaper way to have high quality builds.
- **Swappable head.** The aim is for one purchase to do more than print. Planned heads: rotary tool (Dremel), refillable-ink 2D printer, camera, lamp, and a hand. A fax machine is on the wish list.
 
*Not for sale, use, or download in California or New York, or any place with restrictions on 3D printers.*
