const libssz = @import("./main.zig");
const serialize = libssz.serialize;
const deserialize = libssz.deserialize;
const chunk_count = libssz.chunk_count;
const hash_tree_root = libssz.hash_tree_root;
const build_zeroes = libssz.build_zeroes;
const std = @import("std");
const ArrayList = std.ArrayList;
const expect = std.testing.expect;
const sha256 = std.crypto.hash.sha2.Sha256;

test "serializes uint8" {
    var data: u8 = 0x55;
    const serialized_data = [_]u8{0x55};

    var list = ArrayList(u8).init(std.testing.allocator);
    defer list.deinit();
    try serialize(u8, data, &list);
    expect(std.mem.eql(u8, list.items, serialized_data[0..]));
}

test "serializes uint16" {
    var data: u16 = 0x5566;
    const serialized_data = [_]u8{ 0x66, 0x55 };

    var list = ArrayList(u8).init(std.testing.allocator);
    defer list.deinit();
    try serialize(u16, data, &list);
    expect(std.mem.eql(u8, list.items, serialized_data[0..]));
}

test "serializes uint32" {
    var data: u32 = 0x55667788;
    const serialized_data = [_]u8{ 0x88, 0x77, 0x66, 0x55 };

    var list = ArrayList(u8).init(std.testing.allocator);
    defer list.deinit();
    try serialize(u32, data, &list);
    expect(std.mem.eql(u8, list.items, serialized_data[0..]));
}

test "serializes a int32" {
    var data: i32 = -(0x11223344);
    const serialized_data = [_]u8{ 0xbc, 0xcc, 0xdd, 0xee };

    var list = ArrayList(u8).init(std.testing.allocator);
    defer list.deinit();
    try serialize(i32, data, &list);
    expect(std.mem.eql(u8, list.items, serialized_data[0..]));
}

test "serializes bool" {
    var data = false;
    var serialized_data = [_]u8{0x00};

    var list = ArrayList(u8).init(std.testing.allocator);
    defer list.deinit();
    try serialize(bool, data, &list);
    expect(std.mem.eql(u8, list.items, serialized_data[0..]));

    data = true;
    serialized_data = [_]u8{0x01};

    var list2 = ArrayList(u8).init(std.testing.allocator);
    defer list2.deinit();
    try serialize(bool, data, &list2);
    expect(std.mem.eql(u8, list2.items, serialized_data[0..]));
}

test "serializes Bitvector[N] == [N]bool" {
    var data7 = [_]bool{ true, false, true, true, false, false, false };
    var serialized_data = [_]u8{0b00001101};
    var exp = serialized_data[0..serialized_data.len];

    var list7 = ArrayList(u8).init(std.testing.allocator);
    defer list7.deinit();
    try serialize([7]bool, data7, &list7);
    expect(std.mem.eql(u8, list7.items, exp));

    var data8 = [_]bool{ true, false, true, true, false, false, false, true };
    serialized_data = [_]u8{0b10001101};
    exp = serialized_data[0..serialized_data.len];

    var list8 = ArrayList(u8).init(std.testing.allocator);
    defer list8.deinit();
    try serialize([8]bool, data8, &list8);
    expect(std.mem.eql(u8, list8.items, exp));

    var data12 = [_]bool{ true, false, true, true, false, false, false, true, false, true, false, true };

    var list12 = ArrayList(u8).init(std.testing.allocator);
    defer list12.deinit();
    try serialize([12]bool, data12, &list12);
    expect(list12.items.len == 2);
    expect(list12.items[0] == 141);
    expect(list12.items[1] == 10);
}

test "serializes string" {
    const data = "zig zag";

    var list = ArrayList(u8).init(std.testing.allocator);
    defer list.deinit();
    try serialize([]const u8, data, &list);
    expect(std.mem.eql(u8, list.items, data));
}

test "serializes an array of shorts" {
    const data = [_]u16{ 0xabcd, 0xef01 };
    const serialized = [_]u8{ 0xcd, 0xab, 0x01, 0xef };

    var list = ArrayList(u8).init(std.testing.allocator);
    defer list.deinit();
    try serialize([]const u16, data[0..data.len], &list);
    expect(std.mem.eql(u8, list.items, serialized[0..]));
}

test "serializes an array of structures" {
    var list = ArrayList(u8).init(std.testing.allocator);
    defer list.deinit();
    const exp = [_]u8{ 8, 0, 0, 0, 23, 0, 0, 0, 6, 0, 0, 0, 20, 0, 99, 114, 111, 105, 115, 115, 97, 110, 116, 6, 0, 0, 0, 244, 1, 72, 101, 114, 114, 101, 110, 116, 111, 114, 116, 101 };

    try serialize(@TypeOf(pastries), pastries, &list);
    expect(std.mem.eql(u8, list.items, exp[0..]));
}

test "serializes a structure without variable fields" {
    var data = .{
        .uint8 = @as(u8, 1),
        .uint32 = @as(u32, 3),
        .boolean = true,
    };
    const serialized_data = [_]u8{ 1, 3, 0, 0, 0, 1 };

    var list = ArrayList(u8).init(std.testing.allocator);
    defer list.deinit();
    try serialize(@TypeOf(data), data, &list);
    expect(std.mem.eql(u8, list.items, serialized_data[0..]));
}

test "serializes a structure with variable fields" {
    // Taken from ssz.cr
    const data = .{
        .name = "James",
        .age = @as(u8, 32),
        .company = "DEV Inc.",
    };
    const serialized_data = [_]u8{ 9, 0, 0, 0, 32, 14, 0, 0, 0, 74, 97, 109, 101, 115, 68, 69, 86, 32, 73, 110, 99, 46 };

    var list = ArrayList(u8).init(std.testing.allocator);
    defer list.deinit();
    try serialize(@TypeOf(data), data, &list);
    expect(std.mem.eql(u8, list.items, serialized_data[0..]));
}

test "serializes a structure with optional fields" {
    const Employee = struct {
        name: ?[]const u8,
        age: u8,
        company: ?[]const u8,
    };
    const data: Employee = .{
        .name = "James",
        .age = @as(u8, 32),
        .company = null,
    };

    const serialized_data = [_]u8{ 9, 0, 0, 0, 32, 14, 0, 0, 0, 74, 97, 109, 101, 115 };

    var list = ArrayList(u8).init(std.testing.allocator);
    defer list.deinit();
    try serialize(@TypeOf(data), data, &list);
    expect(std.mem.eql(u8, list.items, serialized_data[0..]));
}

test "serializes an optional object" {
    const null_or_string: ?[]const u8 = null;
    var list = ArrayList(u8).init(std.testing.allocator);
    defer list.deinit();
    try serialize(@TypeOf(null_or_string), null_or_string, &list);
    expect(list.items.len == 0);
}

test "serializes a union" {
    const Payload = union(enum) {
        int: u64,
        boolean: bool,
    };

    var list = ArrayList(u8).init(std.testing.allocator);
    defer list.deinit();
    const exp = [_]u8{ 0, 0, 0, 0, 210, 4, 0, 0, 0, 0, 0, 0 };
    try serialize(Payload, Payload{ .int = 1234 }, &list);
    expect(std.mem.eql(u8, list.items, exp[0..]));

    var list2 = ArrayList(u8).init(std.testing.allocator);
    defer list2.deinit();
    const exp2 = [_]u8{ 1, 0, 0, 0, 1 };
    try serialize(Payload, Payload{ .boolean = true }, &list2);
    expect(std.mem.eql(u8, list2.items, exp2[0..]));

    // Make sure that the code won't try to serialize untagged
    // payloads.
    const UnTaggedPayload = union {
        int: u64,
        boolean: bool,
    };

    var list3 = ArrayList(u8).init(std.testing.allocator);
    defer list3.deinit();
    if (serialize(UnTaggedPayload, UnTaggedPayload{ .boolean = false }, &list3)) {
        @panic("didn't catch error");
    } else |err| switch (err) {
        error.UnionIsNotTagged => {},
        else => @panic("invalid error"),
    }
}

test "deserializes an u8" {
    const payload = [_]u8{0x55};
    var i: u8 = 0;
    try deserialize(u8, payload[0..payload.len], &i);
    expect(i == 0x55);
}

test "deserializes an u32" {
    const payload = [_]u8{ 0x55, 0x66, 0x77, 0x88 };
    var i: u32 = 0;
    try deserialize(u32, payload[0..payload.len], &i);
    expect(i == 0x88776655);
}

test "deserializes a boolean" {
    const payload_false = [_]u8{0};
    var b = true;
    try deserialize(bool, payload_false[0..1], &b);
    expect(b == false);

    const payload_true = [_]u8{1};
    try deserialize(bool, payload_true[0..1], &b);
    expect(b == true);
}

test "deserializes a Bitvector[N]" {
    const exp = [_]bool{ true, false, true, true, false, false, false };
    var out = [_]bool{ false, false, false, false, false, false, false };
    const serialized_data = [_]u8{0b00001101};
    try deserialize([7]bool, serialized_data[0..1], &out);
    comptime var i = 0;
    inline while (i < 7) : (i += 1) {
        expect(out[i] == exp[i]);
    }
}

test "deserializes an Optional" {
    var list = ArrayList(u8).init(std.testing.allocator);
    defer list.deinit();

    var out: ?u32 = undefined;
    const exp: ?u32 = 10;
    try serialize(?u32, exp, &list);
    try deserialize(?u32, list.items, &out);
    expect(out.? == exp.?);

    var list2 = ArrayList(u8).init(std.testing.allocator);
    defer list2.deinit();

    try serialize(?u32, null, &list2);
    try deserialize(?u32, list2.items, &out);
    expect(out == null);
}

test "deserializes a string" {
    const exp = "croissants";

    var list = ArrayList(u8).init(std.testing.allocator);
    defer list.deinit();
    const serialized = try serialize([]const u8, exp, &list);

    var got: []const u8 = undefined;

    try deserialize([]const u8, list.items, &got);
    expect(std.mem.eql(u8, exp, got));
}

const Pastry = struct {
    name: []const u8,
    weight: u16,
};

const pastries = [_]Pastry{
    Pastry{
        .name = "croissant",
        .weight = 20,
    },
    Pastry{
        .name = "Herrentorte",
        .weight = 500,
    },
};

test "deserializes a structure" {
    var out = Pastry{ .name = "", .weight = 0 };
    var list = ArrayList(u8).init(std.testing.allocator);
    defer list.deinit();

    try serialize(Pastry, pastries[0], &list);
    try deserialize(Pastry, list.items, &out);

    expect(pastries[0].weight == out.weight);
    expect(std.mem.eql(u8, pastries[0].name, out.name));
}

test "deserializes a Vector[N]" {
    var out: [2]Pastry = undefined;
    var list = ArrayList(u8).init(std.testing.allocator);
    defer list.deinit();

    try serialize([2]Pastry, pastries, &list);
    try deserialize(@TypeOf(pastries), list.items, &out);
    comptime var i = 0;
    inline while (i < pastries.len) : (i += 1) {
        expect(out[i].weight == pastries[i].weight);
        expect(std.mem.eql(u8, pastries[i].name, out[i].name));
    }
}

test "deserializes an invalid Vector[N] payload" {
    var out: [2]Pastry = undefined;
    var list = ArrayList(u8).init(std.testing.allocator);
    defer list.deinit();

    try serialize([2]Pastry, pastries, &list);
    if (deserialize(@TypeOf(pastries), list.items[0 .. list.items.len / 2], &out)) {
        @panic("missed error");
    } else |err| switch (err) {
        error.IndexOutOfBounds => {},
        else => {
            @panic("unexpected error");
        },
    }
}

test "deserializes an union" {
    const Payload = union {
        int: u32,
        boolean: bool,
    };

    var p: Payload = undefined;
    try deserialize(Payload, ([_]u8{ 1, 0, 0, 0, 1 })[0..], &p);
    expect(p.boolean == true);

    try deserialize(Payload, ([_]u8{ 1, 0, 0, 0, 0 })[0..], &p);
    expect(p.boolean == false);

    try deserialize(Payload, ([_]u8{ 0, 0, 0, 0, 1, 2, 3, 4 })[0..], &p);
    expect(p.int == 0x04030201);
}

test "serialize/deserialize a u256" {
    var list = ArrayList(u8).init(std.testing.allocator);
    defer list.deinit();
    const data = [_]u8{0xAA} ** 32;
    var output: [32]u8 = undefined;

    try serialize([32]u8, data, &list);
    try deserialize([32]u8, list.items, &output);

    expect(std.mem.eql(u8, data[0..], output[0..]));
}

test "chunk count of basic types" {
    expect(chunk_count(bool) == 1);
    expect(chunk_count(u8) == 1);
    expect(chunk_count(u16) == 1);
    expect(chunk_count(u32) == 1);
    expect(chunk_count(u64) == 1);
}

test "chunk count of Bitvector[N]" {
    expect(chunk_count([7]bool) == 1);
    expect(chunk_count([12]bool) == 1);
    expect(chunk_count([384]bool) == 2);
}

test "chunk count of Vector[B, N]" {
    expect(chunk_count([17]u32) == 3);
}

test "chunk count of a struct" {
    expect(chunk_count(Pastry) == 2);
}

test "chunk count of a Vector[C, N]" {
    expect(chunk_count([2]Pastry) == 2);
}

// used at comptime to generate a bitvector from a byte vector
fn bytes_to_bits(comptime N: usize, src: [N]u8) [N * 8]bool {
    var bitvector: [N * 8]bool = undefined;
    for (src) |byte, idx| {
        var i = 0;
        while (i < 8) : (i += 1) {
            bitvector[i + idx * 8] = ((byte >> (7 - i)) & 1) == 1;
        }
    }
    return bitvector;
}

const a_bytes = [_]u8{0xaa} ** 16;
const b_bytes = [_]u8{0xbb} ** 16;
const c_bytes = [_]u8{0xcc} ** 16;
const d_bytes = [_]u8{0xdd} ** 16;
const e_bytes = [_]u8{0xee} ** 16;
const empty_bytes = [_]u8{0} ** 16;

const a_bits = bytes_to_bits(16, a_bytes);
const b_bits = bytes_to_bits(16, b_bytes);
const c_bits = bytes_to_bits(16, c_bytes);
const d_bits = bytes_to_bits(16, d_bytes);
const e_bits = bytes_to_bits(16, e_bytes);

test "calculate the root hash of a boolean" {
    build_zeroes();
    var expected = [_]u8{1} ++ [_]u8{0} ** 31;
    var hashed: [32]u8 = undefined;
    try hash_tree_root(bool, true, &hashed);
    std.testing.expect(std.mem.eql(u8, hashed[0..], expected[0..]));

    expected = [_]u8{0} ** 32;
    try hash_tree_root(bool, false, &hashed);
    std.testing.expect(std.mem.eql(u8, hashed[0..], expected[0..]));
}

test "calculate root hash of an array of two Bitvector[128]" {
    build_zeroes();
    var deserialized: [2][128]bool = [2][128]bool{ a_bits, b_bits };
    var hashed: [32]u8 = undefined;
    try hash_tree_root(@TypeOf(deserialized), deserialized, &hashed);

    var expected: [32]u8 = undefined;
    const expected_preimage = a_bytes ++ empty_bytes ++ b_bytes ++ empty_bytes;
    sha256.hash(expected_preimage[0..], &expected, sha256.Options{});

    std.testing.expect(std.mem.eql(u8, hashed[0..], expected[0..]));
}

test "calculate the root hash of an array of integers" {
    build_zeroes();
    var expected = [_]u8{ 0xef, 0xbe, 0xad, 0xde, 0xfe, 0xca, 0xfe, 0xca } ++ [_]u8{0} ** 24;
    var hashed: [32]u8 = undefined;
    try hash_tree_root([2]u32, [_]u32{ 0xdeadbeef, 0xcafecafe }, &hashed);
    std.testing.expect(std.mem.eql(u8, hashed[0..], expected[0..]));
}

test "calculate root hash of an array of three Bitvector[128]" {
    build_zeroes();
    var deserialized: [3][128]bool = [3][128]bool{ a_bits, b_bits, c_bits };
    var hashed: [32]u8 = undefined;
    try hash_tree_root(@TypeOf(deserialized), deserialized, &hashed);

    var left: [32]u8 = undefined;
    var expected: [32]u8 = undefined;
    const preimg1 = a_bytes ++ empty_bytes ++ b_bytes ++ empty_bytes;
    const preimg2 = c_bytes ++ empty_bytes ** 3;
    sha256.hash(preimg1[0..], &left, sha256.Options{});
    sha256.hash(preimg2[0..], &expected, sha256.Options{});
    var digest = sha256.init(sha256.Options{});
    digest.update(left[0..]);
    digest.update(expected[0..]);
    digest.final(&expected);

    std.testing.expect(std.mem.eql(u8, hashed[0..], expected[0..]));
}

test "calculate the root hash of an array of five Bitvector[128]" {
    build_zeroes();
    var deserialized = [5][128]bool{ a_bits, b_bits, c_bits, d_bits, e_bits };
    var hashed: [32]u8 = undefined;
    try hash_tree_root(@TypeOf(deserialized), deserialized, &hashed);

    var internal_nodes: [64]u8 = undefined;
    var left: [32]u8 = undefined;
    var expected: [32]u8 = undefined;
    const preimg1 = a_bytes ++ empty_bytes ++ b_bytes ++ empty_bytes;
    const preimg2 = c_bytes ++ empty_bytes ++ d_bytes ++ empty_bytes;
    const preimg3 = e_bytes ++ empty_bytes ** 3;
    const preimg4 = empty_bytes ** 4;

    sha256.hash(preimg1[0..], &left, sha256.Options{});
    sha256.hash(preimg2[0..], internal_nodes[0..32], sha256.Options{});
    var digest = sha256.init(sha256.Options{});
    digest.update(left[0..]);
    digest.update(internal_nodes[0..32]);
    digest.final(internal_nodes[0..32]);

    sha256.hash(preimg3[0..], &left, sha256.Options{});
    sha256.hash(preimg4[0..], internal_nodes[32..], sha256.Options{});
    digest = sha256.init(sha256.Options{});
    digest.update(left[0..]);
    digest.update(internal_nodes[32..]);
    digest.final(internal_nodes[32..]);

    sha256.hash(internal_nodes[0..], &expected, sha256.Options{});

    std.testing.expect(std.mem.eql(u8, hashed[0..], expected[0..]));
}
