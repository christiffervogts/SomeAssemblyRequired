/* stl2ascii.c: convert a binary STL file to ASCII STL.
 *
 * Compile: gcc -O2 stl2ascii.c -o stl2ascii
 * Run:     ./stl2ascii Benchy.stl Benchy_ascii.stl
 *
 * Binary STL layout (little-endian):
 *   80 bytes  header
 *    4 bytes  uint32 triangle count
 *   per triangle (50 bytes):
 *       3 x float32 normal
 *       9 x float32 vertices (x1 y1 z1 x2 y2 z2 x3 y3 z3)
 *       1 x uint16  attribute
 */
#include <stdio.h>
#include <stdint.h>

int main(int argc, char *argv[])
{
    if (argc != 3) {
        fprintf(stderr, "usage: %s input.stl output.stl\n", argv[0]);
        return 1;
    }

    FILE *in  = fopen(argv[1], "rb");
    FILE *out = fopen(argv[2], "w");
    if (!in || !out) {
        fprintf(stderr, "could not open files\n");
        return 1;
    }

    char header[80];
    uint32_t ntri;
    if (fread(header, 1, 80, in) != 80 || fread(&ntri, 4, 1, in) != 1) {
        fprintf(stderr, "file too short to be an STL\n");
        return 1;
    }

    fprintf(out, "solid converted\n");

    for (uint32_t i = 0; i < ntri; i++) {
        float n[3], v[9];
        uint16_t attr;

        if (fread(n, 4, 3, in) != 3 ||
            fread(v, 4, 9, in) != 9 ||
            fread(&attr, 2, 1, in) != 1) {
            fprintf(stderr, "file ended early at triangle %u\n", i);
        return 1;
            }

            fprintf(out, "facet normal %e %e %e\n", n[0], n[1], n[2]);
            fprintf(out, "  outer loop\n");
            for (int k = 0; k < 3; k++)
                fprintf(out, "    vertex %e %e %e\n", v[3*k], v[3*k+1], v[3*k+2]);
        fprintf(out, "  endloop\n");
        fprintf(out, "endfacet\n");
    }

    fprintf(out, "endsolid converted\n");

    fclose(in);
    fclose(out);
    return 0;
}
