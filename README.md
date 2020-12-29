[![CircleCI](https://circleci.com/gh/gballet/ssz.zig.svg?style=shield)](https://circleci.com/gh/gballet/ssz.zig)

# ssz.zig
A [Zig](https://ziglang.org) implementation of the [SSZ serialization protocol](https://github.com/ethereum/eth2.0-specs/blob/dev/ssz/simple-serialize.md).

Tested with zig 0.7.0.

## Serialization

Currently supported types:

 * `BitVector[N]`
 * `uintN`
 * `boolean`
 * structures
 * optionals
 * `null`
 * `Vector[N]`

## Deserialization

Supported types:

 * `uintN`
 * `boolean`
 * structures
 * strings
 * `BitVector[N]`
 * `Vector[N]`
 * unions

## Merkelization

TODO

## Contributing

Simply create an issue or a PR.
