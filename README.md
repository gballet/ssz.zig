# ssz.zig
A ziglang implementation of the [SSZ serialization protocol](https://github.com/ethereum/eth2.0-specs/blob/dev/ssz/simple-serialize.md).

Tested with zig 0.7.0.

Currently supported types:
 * `BitVector[N]`
 * `uintN`
 * `boolean`
