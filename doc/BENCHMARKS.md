# Benchmarks

These are measurements on one machine, under the conditions below. They
are not a verdict on either side.

`zig build bench` times the port against the original on the same inputs,
one function at a time, on one thread, and prints a row per case: each
side's median time and spread, the port's time over the original's, and a
throughput where a case says how much one call processes. `zig build bench
-- <text>` runs only the cases whose name holds the text, and `zig build
bench -Dbench-runs=<n>` times `n` calls of each side instead of 11.

The table below combines three runs of the benchmark binary, pinned to one
core:

```sh
zig build bench -- no-such-case      # builds the binary, runs nothing
taskset -c 3 ./.zig-cache/o/<hash>/bench
```

The binary finds the original's shared library through its run path,
relative to the repository's root, so it runs from there.

## Machine and flags

Measured on 23 November 2026, on a cloud virtual machine: 4 virtual CPUs
of an Intel Xeon (Emerald Rapids, 2.1 GHz, AVX-512) under KVM, Linux
6.18.44, Ubuntu 24.04's glibc 2.39, pinned to CPU 3. The "before" column is
commit `a28aebf` (version 0.1.3), the table's times are commit `7c29101`;
the two binaries ran in turns, three runs each, on the same machine.

This is a different machine from the one the first performance pass was
measured on (an AMD Ryzen 9 9950X3D; its table is in this file's history,
at `a28aebf`). Some rows differ a lot between the two: `unstripify` was
1.35 and 0.82 there and 2.00 and 2.53 here before this pass, and
`encodeFilter quat` 0.60 there and 1.61 here.

- **The port:** Zig 0.17.0, ReleaseFast, for the machine's own CPU
  (`emeraldrapids`).
- **The original:** meshoptimizer 1.3 (`f0a684f`), built from source by
  the clang that Zig 0.17.0 carries (22.1.8), for the same CPU, at `-O3
  -std=c++11 -ffp-contract=off -fno-fast-math -fno-exceptions -fno-rtti`,
  with `NDEBUG`, which Zig sets for optimized C++, so its asserts are
  off, as the port's are in ReleaseFast. It is a shared library, as the
  original is usually linked, so its calls into the C library bind to
  glibc's.
- **Both:** no fused multiply-adds, which the tests need for equal
  outputs; scratch memory from the C library's `malloc`, through
  `std.heap.c_allocator` on the port's side and the original's default
  allocator on its side.

## Method

- Each case runs both sides once as a warm-up, then 11 timed calls of
  each, taking turns, so drift in clock speed and cache state falls on both.
- Each call is timed by the monotonic clock, as wall time. A side's time
  for a case is the median of its 11 calls; its spread is the
  interquartile range as a share of that median.
- Every constant the port's calls take goes through a volatile load, and
  every case's inputs are opaque to the compiler, so LLVM cannot
  specialize the port on the benchmark's sizes and options, which it
  cannot do for the original's separately built library either. Every
  result and output stays observable, so no work is dropped.
- The benchmark ran three times for each commit. Each row's time is the
  median of the three runs' medians, and its ratio the median of the three
  runs' ratios, the port's time over the original's: below 1, the port
  takes less time. The range is the lowest and highest ratio of the three
  runs at `7c29101`. "Before" is the median ratio at `a28aebf`.

## Known biases

- **Calls into a shared library.** The original's functions are called
  through the dynamic linker's tables and cannot be inlined into the
  benchmark; the port's can. For a function that does little per call,
  such as `quantizeHalf` on one value, this is most of the difference.
  The header's inline functions (`quantizeUnorm`, `quantizeSnorm`) are
  compiled into the benchmark's C++ shim, so their loops inline as they do
  in a C++ caller.
- **Vectorization.** Zig 0.17 does not vectorize loops by itself, where
  clang does at `-O3`. The port's hot loops are written on `@Vector`s
  where the original's loops vectorize; loops the original relies on
  clang to vectorize and the port does not yet are among the slower rows
  below.
- **A shared virtual machine.** The runs were on 4 virtual CPUs of a
  cloud machine, with nothing else running in it, but its host's other
  tenants are not under control: a side's spread within a case is often
  10 to 30% of its median. Taking turns and taking the median of three runs
  keeps the ratios steadier than the times (their ranges are given), but a
  ratio within a few hundredths of 1 is not a difference.

## Results

The inputs: `pirate` is the original's demo mesh, a few thousand
triangles; `sphere 1M` is a generated sphere of about a million
triangles (`sphere 262k`, about a quarter million); `1M` rows run on
about a million values. Each mesh's vertices are 32 bytes: a position, a
normal and texture coordinates. Cases with `u16` in their name take
16-bit indices, against the original's 16-bit templates.

Over all 218 cases, the port's time is at most 1.05 of the original's in
198 (164 before this pass, on this machine), and below the original's in
133 (117 before).

| case | before ÷ original | original µs | port µs | port ÷ original | range |
| --- | ---: | ---: | ---: | ---: | ---: |
| quantizeHalf 1M | 0.79 | 1,794 | 1,488 | 0.83 | 0.79 to 0.85 |
| dequantizeHalf 1M | 0.65 | 1,520 | 854.3 | 0.57 | 0.55 to 0.57 |
| quantizeFloat 1M | 0.24 | 3,066 | 742.7 | 0.24 | 0.23 to 0.30 |
| quantizeUnorm 1M | 2.78 | 373.4 | 1,002 | 2.68 | 2.66 to 2.88 |
| quantizeSnorm 1M | 3.00 | 349.0 | 1,032 | 2.96 | 2.88 to 3.00 |
| quantizeUnorm x16 1M | 1.00 | 354.1 | 373.9 | 1.05 | 0.98 to 1.06 |
| quantizeSnorm x16 1M | 1.02 | 375.6 | 380.3 | 1.00 | 0.98 to 1.01 |
| computePositionExponent 1M | 0.72 | 27,416 | 19,972 | 0.73 | 0.72 to 0.73 |
| generateVertexRemap pirate | 1.02 | 201.7 | 160.6 | 0.80 | 0.79 to 0.81 |
| generateVertexRemapMulti pirate | 1.06 | 311.1 | 294.4 | 0.96 | 0.94 to 0.96 |
| generateVertexRemapCustom pirate | 0.79 | 100.6 | 62.1 | 0.62 | 0.62 to 0.63 |
| remapVertexBuffer pirate | 1.52 | 21.9 | 22.0 | 0.99 | 0.99 to 1.01 |
| remapIndexBuffer pirate | 1.12 | 1.7 | 1.8 | 1.12 | 1.09 to 1.17 |
| generateShadowIndexBuffer pirate | 1.23 | 51.2 | 66.4 | 1.31 | 1.24 to 1.32 |
| generateShadowIndexBufferMulti pirate | 0.94 | 69.1 | 63.9 | 0.92 | 0.90 to 0.95 |
| filterIndexBuffer pirate | 1.07 | 163.3 | 161.5 | 0.98 | 0.95 to 1.05 |
| filterIndexBufferMulti pirate | 0.97 | 162.7 | 161.6 | 1.00 | 0.99 to 1.00 |
| generateProvokingIndexBuffer pirate | 0.98 | 43.6 | 43.1 | 0.99 | 0.94 to 1.01 |
| generateVertexRemap sphere 1M | 1.03 | 117,244 | 66,648 | 0.56 | 0.53 to 0.61 |
| generateVertexRemapMulti sphere 1M | 1.16 | 145,361 | 94,532 | 0.65 | 0.60 to 0.69 |
| generateVertexRemapCustom sphere 1M | 1.02 | 53,788 | 38,653 | 0.73 | 0.69 to 0.73 |
| remapVertexBuffer sphere 1M | 1.19 | 15,118 | 14,748 | 0.98 | 0.97 to 0.98 |
| remapIndexBuffer sphere 1M | 0.97 | 1,083 | 1,073 | 0.99 | 0.99 to 1.04 |
| generateShadowIndexBuffer sphere 1M | 1.16 | 14,852 | 17,252 | 1.15 | 1.04 to 1.16 |
| generateShadowIndexBufferMulti sphere 1M | 1.03 | 14,200 | 15,036 | 1.06 | 1.04 to 1.08 |
| filterIndexBuffer sphere 1M | 1.08 | 73,075 | 66,789 | 0.92 | 0.89 to 0.94 |
| filterIndexBufferMulti sphere 1M | 1.07 | 67,960 | 62,294 | 0.94 | 0.91 to 0.95 |
| generateProvokingIndexBuffer sphere 1M | 1.04 | 7,422 | 7,725 | 1.04 | 1.02 to 1.04 |
| optimizeOverdraw pirate | 1.06 | 131.1 | 139.5 | 1.08 | 1.06 to 1.10 |
| optimizeVertexFetch pirate | 0.51 | 41.2 | 35.6 | 0.87 | 0.86 to 0.90 |
| stripify pirate | 1.05 | 194.1 | 203.1 | 1.05 | 1.00 to 1.08 |
| spatialSortTriangles pirate | 0.91 | 78.1 | 68.2 | 0.92 | 0.87 to 0.95 |
| spatialClusterPoints pirate | 0.99 | 61.7 | 63.2 | 1.02 | 1.02 to 1.03 |
| spatialSortRemap pirate | 0.93 | 35.7 | 32.8 | 0.92 | 0.92 to 0.93 |
| analyzeVertexCache pirate | 0.97 | 36.1 | 37.1 | 1.00 | 0.92 to 1.03 |
| analyzeVertexFetch pirate | 1.15 | 22.4 | 25.1 | 1.12 | 0.95 to 1.13 |
| analyzeOverdraw pirate | 1.05 | 1,505 | 1,561 | 1.03 | 1.02 to 1.04 |
| analyzeCoverage pirate | 1.04 | 1,476 | 1,536 | 1.02 | 1.01 to 1.04 |
| optimizeVertexFetchRemap pirate | 0.85 | 21.1 | 15.9 | 0.74 | 0.51 to 0.75 |
| unstripify pirate | 2.00 | 18.3 | 13.9 | 0.77 | 0.76 to 0.78 |
| generatePositionRemap pirate | 0.92 | 21.1 | 20.2 | 0.96 | 0.93 to 0.96 |
| generateAdjacencyIndexBuffer pirate | 1.05 | 310.9 | 318.9 | 1.00 | 0.97 to 1.03 |
| generateTessellationIndexBuffer pirate | 0.98 | 308.9 | 293.2 | 0.94 | 0.93 to 0.96 |
| optimizeOverdraw sphere 1M | 1.03 | 20,968 | 21,692 | 1.04 | 1.03 to 1.06 |
| optimizeVertexFetch sphere 1M | 0.79 | 6,755 | 4,595 | 0.78 | 0.68 to 0.79 |
| stripify sphere 1M | 0.93 | 28,946 | 26,084 | 0.92 | 0.90 to 0.92 |
| spatialSortTriangles sphere 1M | 0.87 | 50,009 | 43,634 | 0.87 | 0.86 to 0.89 |
| spatialClusterPoints sphere 1M | 0.96 | 31,935 | 30,746 | 0.96 | 0.96 to 0.97 |
| spatialSortRemap sphere 1M | 0.96 | 12,190 | 11,798 | 0.97 | 0.97 to 0.97 |
| analyzeVertexCache sphere 1M | 0.96 | 3,544 | 3,428 | 0.96 | 0.96 to 0.98 |
| analyzeVertexFetch sphere 1M | 1.06 | 5,323 | 5,731 | 1.05 | 1.03 to 1.10 |
| analyzeOverdraw sphere 1M | 0.97 | 90,898 | 90,583 | 1.00 | 0.91 to 1.00 |
| analyzeCoverage sphere 1M | 0.98 | 98,662 | 96,058 | 0.95 | 0.92 to 0.99 |
| optimizeVertexFetchRemap sphere 1M | 0.91 | 1,938 | 1,791 | 0.92 | 0.90 to 0.94 |
| unstripify sphere 1M | 2.53 | 1,658 | 1,179 | 0.68 | 0.67 to 0.71 |
| generatePositionRemap sphere 1M | 0.99 | 8,211 | 8,332 | 1.01 | 1.00 to 1.02 |
| generateAdjacencyIndexBuffer sphere 1M | 1.02 | 309,694 | 306,496 | 0.99 | 0.96 to 1.01 |
| generateTessellationIndexBuffer sphere 1M | 0.95 | 278,147 | 273,206 | 0.96 | 0.96 to 1.01 |
| optimizeVertexCache pirate | 0.99 | 764.1 | 762.2 | 1.00 | 1.00 to 1.02 |
| optimizeVertexCacheStrip pirate | 1.02 | 722.3 | 712.4 | 0.99 | 0.98 to 0.99 |
| optimizeVertexCacheFifo pirate | 1.04 | 189.6 | 190.0 | 1.03 | 1.00 to 1.09 |
| buildMeshlets pirate | 0.83 | 2,270 | 1,902 | 0.84 | 0.83 to 0.85 |
| buildMeshletsScan pirate | 0.63 | 40.1 | 23.6 | 0.59 | 0.56 to 0.60 |
| buildMeshletsFlex pirate | 0.84 | 2,230 | 1,900 | 0.84 | 0.83 to 0.85 |
| buildMeshletsSpatial pirate | 1.04 | 968.6 | 975.4 | 1.03 | 1.01 to 1.07 |
| optimizeMeshlet pirate | 1.03 | 143.9 | 142.7 | 1.01 | 0.99 to 1.04 |
| optimizeMeshletLevel 3 pirate | 1.03 | 709.4 | 729.1 | 1.03 | 1.02 to 1.03 |
| computeMeshletBounds pirate | 1.10 | 103.3 | 108.5 | 1.05 | 0.99 to 1.07 |
| computeClusterBounds pirate | 0.82 | 110.9 | 92.0 | 0.83 | 0.83 to 0.84 |
| extractMeshletIndices pirate | 0.92 | 37.9 | 34.0 | 0.91 | 0.89 to 0.91 |
| computeSphereBounds points pirate | 0.61 | 21.4 | 13.1 | 0.61 | 0.61 to 0.61 |
| computeSphereBounds spheres pirate | 0.63 | 21.4 | 13.4 | 0.63 | 0.63 to 0.63 |
| partitionClusters pirate | 0.85 | 53.8 | 44.7 | 0.87 | 0.80 to 0.87 |
| optimizeVertexCache sphere 1M | 0.99 | 94,496 | 93,806 | 1.00 | 0.99 to 1.01 |
| optimizeVertexCacheStrip sphere 1M | 0.86 | 177,748 | 156,886 | 0.89 | 0.87 to 0.90 |
| optimizeVertexCacheFifo sphere 1M | 0.95 | 31,439 | 29,711 | 0.95 | 0.95 to 0.99 |
| buildMeshlets sphere 1M | 0.84 | 701,822 | 584,119 | 0.83 | 0.82 to 0.88 |
| buildMeshletsScan sphere 1M | 0.88 | 5,413 | 4,511 | 0.83 | 0.82 to 0.83 |
| buildMeshletsFlex sphere 1M | 0.83 | 708,006 | 577,476 | 0.83 | 0.82 to 0.83 |
| buildMeshletsSpatial sphere 1M | 1.06 | 509,931 | 546,473 | 1.07 | 1.02 to 1.12 |
| optimizeMeshlet sphere 1M | 0.99 | 31,646 | 32,679 | 1.03 | 1.00 to 1.03 |
| optimizeMeshletLevel 3 sphere 1M | 1.07 | 158,336 | 162,841 | 1.03 | 1.03 to 1.05 |
| computeMeshletBounds sphere 1M | 1.03 | 33,251 | 34,021 | 1.02 | 0.95 to 1.05 |
| computeClusterBounds sphere 1M | 0.91 | 43,283 | 38,681 | 0.89 | 0.89 to 0.90 |
| extractMeshletIndices sphere 1M | 0.72 | 60,141 | 43,111 | 0.72 | 0.72 to 0.72 |
| computeSphereBounds points sphere 1M | 0.55 | 5,436 | 3,117 | 0.57 | 0.56 to 0.58 |
| computeSphereBounds spheres sphere 1M | 0.56 | 5,410 | 3,056 | 0.57 | 0.56 to 0.58 |
| partitionClusters sphere 1M | 1.04 | 23,952 | 24,984 | 1.04 | 1.04 to 1.06 |
| optimizeVertexCache u16 pirate | 0.99 | 767.8 | 753.9 | 0.98 | 0.98 to 0.99 |
| simplify u16 pirate | 1.03 | 1,374 | 1,396 | 1.02 | 0.99 to 1.03 |
| buildMeshlets u16 pirate | 0.86 | 2,207 | 1,859 | 0.84 | 0.84 to 0.87 |
| encodeIndexBuffer pirate | 0.95 | 7,894 | 7,897 | 1.00 | 0.98 to 1.03 |
| decodeIndexBuffer u32 pirate | 0.94 | 1,271 | 1,232 | 0.94 | 0.75 to 0.97 |
| decodeIndexBuffer u16 pirate | 0.94 | 1,374 | 1,283 | 0.94 | 0.93 to 0.95 |
| encodeIndexSequence pirate | 0.99 | 3,293 | 3,226 | 0.99 | 0.98 to 1.03 |
| decodeIndexSequence pirate | 0.70 | 3,190 | 2,244 | 0.70 | 0.68 to 0.77 |
| encodeMeshlet pirate | 0.97 | 3,982 | 3,957 | 0.99 | 0.99 to 1.00 |
| decodeMeshlet u32/u8 pirate | 0.94 | 423.2 | 430.8 | 0.98 | 0.95 to 1.02 |
| decodeMeshlet u16/u32 pirate | 0.96 | 463.9 | 433.5 | 0.95 | 0.93 to 0.96 |
| decodeMeshletRaw pirate | 0.97 | 452.5 | 443.1 | 0.99 | 0.98 to 1.00 |
| encodeIndexBuffer sphere 1M | 1.03 | 13,360 | 13,601 | 1.02 | 1.02 to 1.02 |
| decodeIndexBuffer u32 sphere 1M | 0.96 | 2,784 | 2,614 | 0.92 | 0.87 to 0.95 |
| decodeIndexBuffer u16 sphere 1M | 0.96 | 2,582 | 2,503 | 0.97 | 0.96 to 0.99 |
| encodeIndexSequence sphere 1M | 1.00 | 8,268 | 8,089 | 1.00 | 0.98 to 1.01 |
| decodeIndexSequence sphere 1M | 0.69 | 6,139 | 4,354 | 0.69 | 0.68 to 0.71 |
| encodeMeshlet sphere 1M | 1.02 | 8,539 | 8,401 | 1.02 | 0.79 to 1.02 |
| decodeMeshlet u32/u8 sphere 1M | 0.96 | 933.6 | 895.1 | 0.96 | 0.96 to 0.98 |
| decodeMeshlet u16/u32 sphere 1M | 0.94 | 1,005 | 973.8 | 0.96 | 0.94 to 0.98 |
| decodeMeshletRaw sphere 1M | 0.96 | 932.8 | 912.0 | 0.98 | 0.97 to 1.00 |
| simplify pirate | 1.04 | 1,546 | 1,609 | 1.03 | 1.03 to 1.04 |
| simplifyWithAttributes pirate | 1.08 | 2,176 | 2,300 | 1.05 | 1.05 to 1.06 |
| simplifyWithUpdate pirate | 1.07 | 2,294 | 2,415 | 1.05 | 1.05 to 1.06 |
| simplifySloppy pirate | 1.07 | 121.2 | 125.3 | 1.04 | 1.03 to 1.04 |
| simplifyPrune pirate | 0.93 | 138.8 | 138.3 | 1.00 | 0.97 to 1.00 |
| simplifyPoints pirate | 0.92 | 74.8 | 69.3 | 0.93 | 0.85 to 0.95 |
| simplify sphere 1M | 0.98 | 621,643 | 589,754 | 0.99 | 0.95 to 1.00 |
| simplifyWithAttributes sphere 1M | 1.05 | 1,069,117 | 1,106,820 | 1.05 | 1.03 to 1.06 |
| simplifyWithUpdate sphere 1M | 1.06 | 1,133,794 | 1,130,983 | 1.05 | 0.96 to 1.07 |
| simplifySloppy sphere 1M | 0.95 | 44,127 | 42,037 | 0.95 | 0.92 to 0.96 |
| simplifyPrune sphere 1M | 0.92 | 36,228 | 32,235 | 0.89 | 0.89 to 0.91 |
| simplifyPoints sphere 1M | 0.95 | 28,956 | 28,866 | 0.98 | 0.89 to 1.00 |
| simplify pirate, allocator cache | 1.04 | 1,572 | 1,693 | 1.08 | 1.03 to 1.08 |
| clusterlod build default(128) pirate | 0.95 | 11,251 | 11,923 | 0.95 | 0.93 to 1.06 |
| clusterlod build defaultRT(128) pirate | 1.02 | 9,235 | 9,215 | 1.01 | 1.00 to 1.01 |
| clusterlod build default(128) sphere 262k | 0.92 | 533,127 | 478,718 | 0.91 | 0.89 to 0.91 |
| clusterlod build defaultRT(128) sphere 262k | 1.03 | 315,740 | 325,868 | 1.03 | 1.03 to 1.05 |
| clusterlod buildHierarchy sphere 262k | 0.92 | 2,779 | 2,540 | 0.90 | 0.90 to 0.93 |
| encodeVertexBuffer v1 L0 pirate | 0.97 | 218.4 | 203.6 | 0.95 | 0.92 to 1.00 |
| decodeVertexBuffer v1 L0 pirate | 1.10 | 31.0 | 31.5 | 1.01 | 0.99 to 1.04 |
| encodeVertexBuffer v1 L1 pirate | 0.98 | 197.6 | 194.1 | 0.98 | 0.97 to 1.02 |
| decodeVertexBuffer v1 L1 pirate | 1.14 | 28.4 | 29.3 | 1.03 | 1.01 to 1.07 |
| encodeVertexBuffer v1 L2 pirate | 1.03 | 234.3 | 228.1 | 1.01 | 0.93 to 1.04 |
| decodeVertexBuffer v1 L2 pirate | 1.11 | 28.5 | 29.7 | 1.03 | 1.01 to 1.04 |
| encodeVertexBuffer v1 L3 pirate | 1.05 | 341.7 | 313.6 | 0.95 | 0.92 to 1.07 |
| decodeVertexBuffer v1 L3 pirate | 1.10 | 21.0 | 21.6 | 1.01 | 1.00 to 1.03 |
| encodeVertexBuffer v0 pirate | 0.98 | 114.8 | 106.9 | 0.96 | 0.93 to 1.03 |
| decodeVertexBuffer v0 pirate | 1.10 | 22.2 | 22.7 | 1.02 | 1.01 to 1.02 |
| encodeVertexBuffer v1 L0 pirate q16 | 0.89 | 63.0 | 56.6 | 0.90 | 0.88 to 0.93 |
| decodeVertexBuffer v1 L0 pirate q16 | 1.06 | 11.6 | 11.6 | 1.00 | 0.99 to 1.01 |
| encodeVertexBuffer v1 L1 pirate q16 | 0.91 | 58.3 | 54.0 | 0.93 | 0.92 to 0.96 |
| decodeVertexBuffer v1 L1 pirate q16 | 1.07 | 11.1 | 11.2 | 1.00 | 0.99 to 1.07 |
| encodeVertexBuffer v1 L2 pirate q16 | 0.92 | 70.4 | 69.4 | 0.99 | 0.89 to 0.99 |
| decodeVertexBuffer v1 L2 pirate q16 | 1.07 | 11.1 | 11.2 | 1.01 | 0.99 to 1.05 |
| encodeVertexBuffer v1 L3 pirate q16 | 0.96 | 102.2 | 96.2 | 0.93 | 0.92 to 0.95 |
| decodeVertexBuffer v1 L3 pirate q16 | 1.05 | 11.1 | 11.2 | 1.01 | 1.00 to 1.06 |
| encodeVertexBuffer v0 pirate q16 | 0.91 | 61.4 | 54.0 | 0.89 | 0.87 to 0.92 |
| decodeVertexBuffer v0 pirate q16 | 1.09 | 11.4 | 11.5 | 1.01 | 0.99 to 1.03 |
| encodeVertexBuffer v1 L0 sphere 1M | 0.94 | 36,797 | 34,410 | 0.94 | 0.93 to 0.96 |
| decodeVertexBuffer v1 L0 sphere 1M | 1.13 | 10,946 | 10,466 | 0.96 | 0.91 to 0.98 |
| encodeVertexBuffer v1 L1 sphere 1M | 0.98 | 33,142 | 31,791 | 0.96 | 0.86 to 0.97 |
| decodeVertexBuffer v1 L1 sphere 1M | 1.19 | 9,291 | 8,761 | 0.93 | 0.92 to 0.94 |
| encodeVertexBuffer v1 L2 sphere 1M | 1.01 | 40,126 | 40,992 | 1.02 | 1.02 to 1.06 |
| decodeVertexBuffer v1 L2 sphere 1M | 1.13 | 9,305 | 8,811 | 0.94 | 0.94 to 0.95 |
| encodeVertexBuffer v1 L3 sphere 1M | 0.98 | 75,508 | 74,169 | 0.98 | 0.95 to 1.04 |
| decodeVertexBuffer v1 L3 sphere 1M | 1.15 | 9,192 | 8,567 | 0.95 | 0.92 to 1.02 |
| encodeVertexBuffer v0 sphere 1M | 0.98 | 36,143 | 35,155 | 0.99 | 0.97 to 0.99 |
| decodeVertexBuffer v0 sphere 1M | 1.15 | 9,468 | 8,957 | 0.96 | 0.95 to 0.98 |
| encodeVertexBuffer v1 L0 sphere 1M q16 | 0.90 | 17,498 | 15,750 | 0.88 | 0.86 to 0.90 |
| decodeVertexBuffer v1 L0 sphere 1M q16 | 1.11 | 3,813 | 3,861 | 1.02 | 1.01 to 1.03 |
| encodeVertexBuffer v1 L1 sphere 1M q16 | 0.97 | 19,277 | 18,148 | 0.94 | 0.92 to 0.97 |
| decodeVertexBuffer v1 L1 sphere 1M q16 | 1.10 | 3,745 | 3,758 | 1.00 | 0.99 to 1.00 |
| encodeVertexBuffer v1 L2 sphere 1M q16 | 1.04 | 18,575 | 19,326 | 1.04 | 0.97 to 1.07 |
| decodeVertexBuffer v1 L2 sphere 1M q16 | 1.06 | 3,864 | 3,600 | 0.93 | 0.91 to 0.98 |
| encodeVertexBuffer v1 L3 sphere 1M q16 | 1.01 | 32,573 | 31,557 | 1.02 | 0.97 to 1.03 |
| decodeVertexBuffer v1 L3 sphere 1M q16 | 1.04 | 3,396 | 3,158 | 0.95 | 0.93 to 0.96 |
| encodeVertexBuffer v0 sphere 1M q16 | 0.98 | 19,620 | 18,424 | 0.95 | 0.94 to 0.95 |
| decodeVertexBuffer v0 sphere 1M q16 | 1.07 | 3,691 | 3,873 | 1.05 | 1.02 to 1.05 |
| encodeFilter oct 8-bit | 1.03 | 27,474 | 28,470 | 1.04 | 1.01 to 1.05 |
| decodeFilter oct 8-bit | 0.56 | 4,586 | 2,711 | 0.59 | 0.57 to 0.62 |
| encodeFilter oct 16-bit | 1.01 | 29,053 | 27,813 | 0.98 | 0.96 to 0.99 |
| decodeFilter oct 16-bit | 0.41 | 6,675 | 2,907 | 0.42 | 0.40 to 0.44 |
| encodeFilter quat | 1.61 | 19,319 | 13,574 | 0.70 | 0.68 to 0.70 |
| decodeFilter quat | 0.52 | 6,432 | 3,410 | 0.55 | 0.52 to 0.55 |
| encodeFilter exp separate | 0.81 | 30,521 | 26,109 | 0.81 | 0.80 to 0.86 |
| decodeFilter exp separate | 0.70 | 2,818 | 2,053 | 0.75 | 0.72 to 0.77 |
| encodeFilter exp shared_vector | 0.71 | 27,413 | 17,842 | 0.65 | 0.62 to 0.68 |
| encodeFilter exp shared_component | 0.53 | 32,327 | 16,449 | 0.51 | 0.50 to 0.54 |
| encodeFilter exp clamped | 0.76 | 29,152 | 22,215 | 0.78 | 0.68 to 0.82 |
| encodeFilter color 8-bit | 1.06 | 28,212 | 28,755 | 1.02 | 1.02 to 1.05 |
| decodeFilter color 8-bit | 0.58 | 3,959 | 2,259 | 0.55 | 0.55 to 0.58 |
| encodeFilter color 16-bit | 1.14 | 28,816 | 31,834 | 1.09 | 1.07 to 1.13 |
| decodeFilter color 16-bit | 0.42 | 6,286 | 2,621 | 0.44 | 0.39 to 0.47 |
| remesh 64 pirate | 1.10 | 1,126 | 1,239 | 1.10 | 1.07 to 1.11 |
| remesh 64 shell pirate | 1.05 | 1,036 | 1,106 | 1.05 | 1.05 to 1.07 |
| remesh 64 solve pirate | 1.11 | 1,380 | 1,496 | 1.08 | 1.07 to 1.10 |
| remesh 128 pirate | 1.09 | 4,494 | 4,851 | 1.09 | 1.08 to 1.09 |
| remesh 128 shell pirate | 1.09 | 3,909 | 4,238 | 1.08 | 1.07 to 1.09 |
| remesh 128 solve pirate | 1.10 | 5,228 | 5,722 | 1.09 | 1.09 to 1.10 |
| remesh 256 pirate | 1.08 | 25,682 | 27,166 | 1.06 | 1.05 to 1.07 |
| remesh 256 shell pirate | 1.08 | 20,779 | 21,995 | 1.06 | 1.06 to 1.07 |
| remesh 256 solve pirate | 1.09 | 28,801 | 31,432 | 1.09 | 1.09 to 1.10 |
| remesh 64 sphere 1M | 0.97 | 66,806 | 65,254 | 0.98 | 0.96 to 0.99 |
| remesh 64 shell sphere 1M | 0.96 | 67,813 | 66,354 | 0.98 | 0.97 to 0.99 |
| remesh 64 solve sphere 1M | 0.99 | 76,005 | 87,845 | 0.99 | 0.98 to 1.16 |
| remesh 128 sphere 1M | 0.98 | 80,882 | 79,105 | 0.98 | 0.97 to 0.98 |
| remesh 128 shell sphere 1M | 0.97 | 79,038 | 77,018 | 0.97 | 0.91 to 0.97 |
| remesh 128 solve sphere 1M | 1.04 | 89,382 | 91,521 | 1.06 | 1.01 to 1.07 |
| remesh 256 sphere 1M | 1.00 | 203,602 | 193,680 | 0.97 | 0.95 to 1.03 |
| remesh 256 shell sphere 1M | 1.00 | 178,730 | 177,295 | 0.99 | 0.98 to 1.01 |
| remesh 256 solve sphere 1M | 1.06 | 213,340 | 222,190 | 1.04 | 1.03 to 1.07 |
| generateTangents pirate | 0.99 | 682.0 | 672.9 | 0.98 | 0.98 to 0.99 |
| generateTangents compatible pirate | 0.98 | 682.5 | 672.7 | 0.98 | 0.97 to 0.99 |
| generateTangents zero fallback pirate | 0.97 | 679.4 | 668.6 | 0.98 | 0.95 to 1.01 |
| generateNormals pirate | 0.99 | 601.9 | 588.8 | 0.98 | 0.97 to 0.98 |
| generateNormals smooth 1.5 pirate | 0.97 | 784.1 | 735.3 | 0.98 | 0.93 to 1.01 |
| generateTangents sphere 1M | 0.96 | 188,357 | 187,155 | 0.99 | 0.91 to 1.02 |
| generateTangents compatible sphere 1M | 1.01 | 184,013 | 181,478 | 0.99 | 0.98 to 1.00 |
| generateTangents zero fallback sphere 1M | 0.97 | 181,253 | 181,579 | 1.01 | 1.00 to 1.01 |
| generateNormals sphere 1M | 0.99 | 114,938 | 114,844 | 1.00 | 0.98 to 1.00 |
| generateNormals smooth 1.5 sphere 1M | 0.96 | 208,424 | 200,182 | 0.96 | 0.96 to 0.98 |
| opacityMapMeasure pirate | 1.00 | 177.2 | 169.5 | 0.96 | 0.96 to 1.00 |
| opacityMapMeasure sphere 1M | 0.96 | 62,420 | 60,101 | 0.95 | 0.94 to 1.01 |
| opacityMapRasterize 2-state pirate | 1.01 | 6,152 | 6,242 | 1.02 | 1.01 to 1.02 |
| opacityMapRasterize 2-state level 10 | 1.00 | 80,541 | 80,129 | 1.00 | 0.99 to 1.01 |
| opacityMapRasterize 2-state level 12 | 1.01 | 1,312,119 | 1,339,437 | 1.02 | 0.99 to 1.02 |
| opacityMapRasterize 4-state pirate | 0.96 | 7,059 | 6,792 | 0.96 | 0.96 to 0.97 |
| opacityMapRasterize 4-state level 10 | 0.98 | 100,007 | 94,865 | 0.96 | 0.95 to 0.97 |
| opacityMapRasterize 4-state level 12 | 0.97 | 1,590,205 | 1,549,839 | 0.99 | 0.94 to 1.04 |

## What this pass changed

Each change keeps the output byte for byte; the oracle tests pass, and
tests were added for the paths they did not reach.

- **`unstripify`** (2.00 and 2.53 to 0.77 and 0.68). LLVM's SLP vectorizer
  packed a triangle's two earlier corners into one vector register and
  shuffled bytes for the winding swap. They are now separate integers and
  the swap two selects; the loop without restart indices is split off, as
  clang unswitches the original's.
- **Vertex remap without an index buffer, and the position remap**
  (`generateVertexRemap`, `-Multi`, `-Custom`; 0.56 to 0.80). On a large
  mesh nearly every hash-table probe misses the caches, on both sides. Each
  vertex's hash is now taken 16 vertices before its lookup and its bucket
  prefetched, so the misses overlap. With an index buffer most indices name
  a vertex already remapped, and the same lookahead cost more than it
  saved, so that path is as before.
- **`filterIndexBuffer`** (1.07 and 1.08 to 0.92 to 0.98). The triangle
  table was filled one 12-byte key at a time; it is now one `memset`. For
  tables over 1 MB, the bucket of the triangle 16 ahead is prefetched.
- **Vertex decoding** (1.06 to 1.19 to 0.93 to 1.05). Whole blocks decode
  straight into the destination instead of into a block buffer that is
  then copied, which the output after an error, unspecified on both sides,
  allows. A full block's literal and zero lanes have a known size, so they
  are a few vector moves instead of calls into compiler_rt's `memcpy` and
  `memset`. A destination over 1 MB is fetched for writing a block ahead,
  since the deltas land 4 bytes at a time across its lines.
- **`encodeFilter quat`** (1.61 to 0.70). Clang vectorizes the original's
  loop, 8 quaternions at a time with gathers; the port now takes 8 at a
  time on `@Vector`s, their components in a vector each.
- **`remapVertexBuffer`** (1.52 and 1.19 to 0.99 and 0.98). Vertices of
  sizes other than 4, 8, 12 and 16 bytes were copied with a `memcpy` call
  each, and compiler_rt's costs more to call than glibc's; up to 64 bytes
  they are now two overlapping moves.
- **`analyzeVertexFetch`**: the miss count without a branch, as the
  original's, and the visited count on vectors (1.15 and 1.06 to 1.12 and
  1.05, within the noise).
- **Simplifier**: the attribute error is inlined into the ranking loop, as
  clang inlines the original's (`simplifyWithAttributes` 1.08 to 1.05 on
  the demo mesh).
- **Remesher**: a row's voxel numbers as a vector prefix sum. Its time on
  the demo mesh hardly moved; see below.

One cause looked for in the disassembly of each profiled hot loop was LLVM
packing independent scalars into one vector register. It was the cause in
`unstripify`. It also shows in the remesher's voxel sums and the
simplifier's attribute error, where the shuffles it adds did not turn out
to be what limits the loop.

## Slower rows

Cases where the port's time is more than 1.05 of the original's, in this
run:

- **`quantizeUnorm` and `quantizeSnorm` as a loop of calls (2.68 and
  2.96).** These are inline functions in the original's header. Clang at
  `-O3` vectorizes a C++ caller's loop of scalar calls into AVX-512 code;
  Zig 0.17 does not auto-vectorize a caller's loop, so the same loop in Zig
  stays scalar, and nothing in the function can change that. The port's
  function also takes a vector of floats, with the same body working lane
  by lane: the `x16` rows call it on vectors of 16 floats against the
  original's loop and take 1.00 and 1.05 of its time.
- **`generateShadowIndexBuffer` (1.31 on the demo mesh, 1.15 on the
  sphere) and `-Multi` on the sphere (1.06).** Both sides spend most of the
  time on one load, the hash table's, which misses the caches; the port's
  loop is the original's, and taking hashes ahead, as the remap now does,
  made it slower, since most indices name a vertex already seen. Part of
  the rest is the two buffers' fill, compiler_rt's `memset` against
  glibc's. Not resolved.
- **The remesher on the demo mesh (1.06 to 1.10) and `remesh 128 solve` on
  the sphere (1.06).** The gap is in voxelizing: the inner loop adds each
  sample to its voxel's sums and quadric, and consecutive samples usually
  hit the same voxel, so it runs at the speed of a load after a store. The
  port's loop and the original's compile to much the same instructions;
  hoisting the per-triangle quadric terms and laying out the voxel as the
  original's did not change the time, and were left out. Not resolved.
- **`buildMeshletsSpatial` on the sphere (1.07, range 1.02 to 1.12).** The
  time is in `bvhSplit`'s box merges and split search, which follow the
  original's SSE code; no cause found.
- **`analyzeVertexFetch` on the demo mesh (1.12, range 0.95 to 1.13)**, a
  25 µs case: the loop is the original's, register allocation in the port
  keeps more on the stack. Not resolved.
- **`remapIndexBuffer` on the demo mesh (1.12)**, a 2 µs case: clang
  vectorizes the original's loop with gathers, and on the sphere both take
  the same time (0.99), so the difference is in the short case's fixed
  costs.
- **`optimizeOverdraw` on the demo mesh (1.08), `encodeFilter color
  16-bit` (1.09) and `simplify pirate, allocator cache` (1.08, range 1.03
  to 1.08).** Not looked into in this pass; the first two were 1.06 and
  1.14 before it.
