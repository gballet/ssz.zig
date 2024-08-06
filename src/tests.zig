const libssz = @import("./main.zig");
const serialize = libssz.serialize;
const deserialize = libssz.deserialize;
const StableContainerFiller = libssz.StableContainerFiller;
const chunkCount = libssz.chunkCount;
const hashTreeRoot = libssz.hashTreeRoot;
const std = @import("std");
const ArrayList = std.ArrayList;
const expect = std.testing.expect;
const sha256 = std.crypto.hash.sha2.Sha256;

test "serializes uint8" {
    const data: u8 = 0x55;
    const serialized_data = [_]u8{0x55};

    var list = ArrayList(u8).init(std.testing.allocator);
    defer list.deinit();
    try serialize(u8, data, &list);
    try expect(std.mem.eql(u8, list.items, serialized_data[0..]));
}

test "serializes uint16" {
    const data: u16 = 0x5566;
    const serialized_data = [_]u8{ 0x66, 0x55 };

    var list = ArrayList(u8).init(std.testing.allocator);
    defer list.deinit();
    try serialize(u16, data, &list);
    try expect(std.mem.eql(u8, list.items, serialized_data[0..]));
}

test "serializes uint32" {
    const data: u32 = 0x55667788;
    const serialized_data = [_]u8{ 0x88, 0x77, 0x66, 0x55 };

    var list = ArrayList(u8).init(std.testing.allocator);
    defer list.deinit();
    try serialize(u32, data, &list);
    try expect(std.mem.eql(u8, list.items, serialized_data[0..]));
}

test "serializes a int32" {
    const data: i32 = -(0x11223344);
    const serialized_data = [_]u8{ 0xbc, 0xcc, 0xdd, 0xee };

    var list = ArrayList(u8).init(std.testing.allocator);
    defer list.deinit();
    try serialize(i32, data, &list);
    try expect(std.mem.eql(u8, list.items, serialized_data[0..]));
}

test "non-byte aligned int serialization fails" {
    const data: u10 = 0x03ff;
    var list = ArrayList(u8).init(std.testing.allocator);
    try std.testing.expectError(error.InvalidSerializedIntLengthType, serialize(u10, data, &list));
}

test "serializes bool" {
    var data = false;
    var serialized_data = [_]u8{0x00};

    var list = ArrayList(u8).init(std.testing.allocator);
    defer list.deinit();
    try serialize(bool, data, &list);
    try expect(std.mem.eql(u8, list.items, serialized_data[0..]));

    data = true;
    serialized_data = [_]u8{0x01};

    var list2 = ArrayList(u8).init(std.testing.allocator);
    defer list2.deinit();
    try serialize(bool, data, &list2);
    try expect(std.mem.eql(u8, list2.items, serialized_data[0..]));
}

test "serializes Bitvector[N] == [N]bool" {
    const data7 = [_]bool{ true, false, true, true, false, false, false };
    var serialized_data = [_]u8{0b00001101};
    var exp = serialized_data[0..serialized_data.len];

    var list7 = ArrayList(u8).init(std.testing.allocator);
    defer list7.deinit();
    try serialize([7]bool, data7, &list7);
    try expect(std.mem.eql(u8, list7.items, exp));

    const data8 = [_]bool{ true, false, true, true, false, false, false, true };
    serialized_data = [_]u8{0b10001101};
    exp = serialized_data[0..serialized_data.len];

    var list8 = ArrayList(u8).init(std.testing.allocator);
    defer list8.deinit();
    try serialize([8]bool, data8, &list8);
    try expect(std.mem.eql(u8, list8.items, exp));

    const data12 = [_]bool{ true, false, true, true, false, false, false, true, false, true, false, true };

    var list12 = ArrayList(u8).init(std.testing.allocator);
    defer list12.deinit();
    try serialize([12]bool, data12, &list12);
    try expect(list12.items.len == 2);
    try expect(list12.items[0] == 141);
    try expect(list12.items[1] == 10);
}

test "serializes string" {
    const data = "zig zag";

    var list = ArrayList(u8).init(std.testing.allocator);
    defer list.deinit();
    try serialize([]const u8, data, &list);
    try expect(std.mem.eql(u8, list.items, data));
}

test "serializes an array of shorts" {
    const data = [_]u16{ 0xabcd, 0xef01 };
    const serialized = [_]u8{ 0xcd, 0xab, 0x01, 0xef };

    var list = ArrayList(u8).init(std.testing.allocator);
    defer list.deinit();
    try serialize([]const u16, data[0..data.len], &list);
    try expect(std.mem.eql(u8, list.items, serialized[0..]));
}

test "serializes an array of structures" {
    var list = ArrayList(u8).init(std.testing.allocator);
    defer list.deinit();
    const exp = [_]u8{ 8, 0, 0, 0, 23, 0, 0, 0, 6, 0, 0, 0, 20, 0, 99, 114, 111, 105, 115, 115, 97, 110, 116, 6, 0, 0, 0, 244, 1, 72, 101, 114, 114, 101, 110, 116, 111, 114, 116, 101 };

    try serialize(@TypeOf(pastries), pastries, &list);
    try expect(std.mem.eql(u8, list.items, exp[0..]));
}

test "serializes a structure without variable fields" {
    const data = .{
        .uint8 = @as(u8, 1),
        .uint32 = @as(u32, 3),
        .boolean = true,
    };
    const serialized_data = [_]u8{ 1, 3, 0, 0, 0, 1 };

    var list = ArrayList(u8).init(std.testing.allocator);
    defer list.deinit();
    try serialize(@TypeOf(data), data, &list);
    try expect(std.mem.eql(u8, list.items, serialized_data[0..]));
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
    try expect(std.mem.eql(u8, list.items, serialized_data[0..]));
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

    const serialized_data = [_]u8{ 9, 0, 0, 0, 32, 15, 0, 0, 0, 1, 74, 97, 109, 101, 115, 0 };

    var list = ArrayList(u8).init(std.testing.allocator);
    defer list.deinit();
    try serialize(@TypeOf(data), data, &list);
    try expect(std.mem.eql(u8, list.items, serialized_data[0..]));

    var deserialized: Employee = undefined;
    try deserialize(Employee, list.items, &deserialized);
    // only available in >=0.11
    // try std.testing.expectEqualDeep(data, deserialized);
    try expect(std.mem.eql(u8, data.name.?, deserialized.name.?));
    try std.testing.expectEqual(data.age, deserialized.age);
    try std.testing.expectEqual(deserialized.company, null);
}

test "serializes an optional object" {
    const null_or_string: ?[]const u8 = null;
    var list = ArrayList(u8).init(std.testing.allocator);
    defer list.deinit();
    try serialize(@TypeOf(null_or_string), null_or_string, &list);
    try expect(list.items.len == 1);
}

test "serializes a union" {
    const Payload = union(enum) {
        int: u64,
        boolean: bool,
    };

    var list = ArrayList(u8).init(std.testing.allocator);
    defer list.deinit();
    const exp = [_]u8{ 0, 210, 4, 0, 0, 0, 0, 0, 0 };
    try serialize(Payload, Payload{ .int = 1234 }, &list);
    try expect(std.mem.eql(u8, list.items, exp[0..]));

    var list2 = ArrayList(u8).init(std.testing.allocator);
    defer list2.deinit();
    const exp2 = [_]u8{ 1, 1 };
    try serialize(Payload, Payload{ .boolean = true }, &list2);
    try expect(std.mem.eql(u8, list2.items, exp2[0..]));

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
    }
}

test "deserializes an u8" {
    const payload = [_]u8{0x55};
    var i: u8 = 0;
    try deserialize(u8, payload[0..payload.len], &i);
    try expect(i == 0x55);
}

test "deserializes an u32" {
    const payload = [_]u8{ 0x55, 0x66, 0x77, 0x88 };
    var i: u32 = 0;
    try deserialize(u32, payload[0..payload.len], &i);
    try expect(i == 0x88776655);
}

test "deserializes a boolean" {
    const payload_false = [_]u8{0};
    var b = true;
    try deserialize(bool, payload_false[0..1], &b);
    try expect(b == false);

    const payload_true = [_]u8{1};
    try deserialize(bool, payload_true[0..1], &b);
    try expect(b == true);
}

test "deserializes a Bitvector[N]" {
    const exp = [_]bool{ true, false, true, true, false, false, false };
    var out = [_]bool{ false, false, false, false, false, false, false };
    const serialized_data = [_]u8{0b00001101};
    try deserialize([7]bool, serialized_data[0..1], &out);
    comptime var i = 0;
    inline while (i < 7) : (i += 1) {
        try expect(out[i] == exp[i]);
    }
}

test "deserializes an Optional" {
    var list = ArrayList(u8).init(std.testing.allocator);
    defer list.deinit();

    var out: ?u32 = undefined;
    const exp: ?u32 = 10;
    try serialize(?u32, exp, &list);
    try deserialize(?u32, list.items, &out);
    try expect(out.? == exp.?);

    var list2 = ArrayList(u8).init(std.testing.allocator);
    defer list2.deinit();

    try serialize(?u32, null, &list2);
    try deserialize(?u32, list2.items, &out);
    try expect(out == null);
}

test "deserializes a string" {
    const exp = "croissants";

    var list = ArrayList(u8).init(std.testing.allocator);
    defer list.deinit();
    try serialize([]const u8, exp, &list);

    var got: []const u8 = undefined;

    try deserialize([]const u8, list.items, &got);
    try expect(std.mem.eql(u8, exp, got));
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

    try expect(pastries[0].weight == out.weight);
    try expect(std.mem.eql(u8, pastries[0].name, out.name));
}

test "deserializes a Vector[N]" {
    var out: [2]Pastry = undefined;
    var list = ArrayList(u8).init(std.testing.allocator);
    defer list.deinit();

    try serialize([2]Pastry, pastries, &list);
    try deserialize(@TypeOf(pastries), list.items, &out);
    comptime var i = 0;
    inline while (i < pastries.len) : (i += 1) {
        try expect(out[i].weight == pastries[i].weight);
        try expect(std.mem.eql(u8, pastries[i].name, out[i].name));
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
    }
}

test "deserializes an union" {
    const Payload = union {
        int: u32,
        boolean: bool,
    };

    var p: Payload = undefined;
    try deserialize(Payload, ([_]u8{ 1, 1 })[0..], &p);
    try expect(p.boolean == true);

    try deserialize(Payload, ([_]u8{ 1, 0 })[0..], &p);
    try expect(p.boolean == false);

    try deserialize(Payload, ([_]u8{ 0, 1, 2, 3, 4 })[0..], &p);
    try expect(p.int == 0x04030201);
}

test "serialize/deserialize a u256" {
    var list = ArrayList(u8).init(std.testing.allocator);
    defer list.deinit();
    const data = [_]u8{0xAA} ** 32;
    var output: [32]u8 = undefined;

    try serialize([32]u8, data, &list);
    try deserialize([32]u8, list.items, &output);

    try expect(std.mem.eql(u8, data[0..], output[0..]));
}

test "chunk count of basic types" {
    try expect(chunkCount(bool) == 1);
    try expect(chunkCount(u8) == 1);
    try expect(chunkCount(u16) == 1);
    try expect(chunkCount(u32) == 1);
    try expect(chunkCount(u64) == 1);
}

test "chunk count of Bitvector[N]" {
    try expect(chunkCount([7]bool) == 1);
    try expect(chunkCount([12]bool) == 1);
    try expect(chunkCount([384]bool) == 2);
}

test "chunk count of Vector[B, N]" {
    try expect(chunkCount([17]u32) == 3);
}

test "chunk count of a struct" {
    try expect(chunkCount(Pastry) == 2);
}

test "chunk count of a Vector[C, N]" {
    try expect(chunkCount([2]Pastry) == 2);
}

// used at comptime to generate a bitvector from a byte vector
fn bytesToBits(comptime N: usize, src: [N]u8) [N * 8]bool {
    var bitvector: [N * 8]bool = undefined;
    for (src, 0..) |byte, idx| {
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

const a_bits = bytesToBits(16, a_bytes);
const b_bits = bytesToBits(16, b_bytes);
const c_bits = bytesToBits(16, c_bytes);
const d_bits = bytesToBits(16, d_bytes);
const e_bits = bytesToBits(16, e_bytes);

test "calculate the root hash of a boolean" {
    var expected = [_]u8{1} ++ [_]u8{0} ** 31;
    var hashed: [32]u8 = undefined;
    try hashTreeRoot(bool, true, &hashed, std.testing.allocator);
    try expect(std.mem.eql(u8, hashed[0..], expected[0..]));

    expected = [_]u8{0} ** 32;
    try hashTreeRoot(bool, false, &hashed, std.testing.allocator);
    try expect(std.mem.eql(u8, hashed[0..], expected[0..]));
}

test "calculate root hash of an array of two Bitvector[128]" {
    const deserialized: [2][128]bool = [2][128]bool{ a_bits, b_bits };
    var hashed: [32]u8 = undefined;
    try hashTreeRoot(@TypeOf(deserialized), deserialized, &hashed, std.testing.allocator);

    var expected: [32]u8 = undefined;
    const expected_preimage = a_bytes ++ empty_bytes ++ b_bytes ++ empty_bytes;
    sha256.hash(expected_preimage[0..], &expected, sha256.Options{});

    try expect(std.mem.eql(u8, hashed[0..], expected[0..]));
}

test "calculate the root hash of an array of integers" {
    var expected = [_]u8{ 0xef, 0xbe, 0xad, 0xde, 0xfe, 0xca, 0xfe, 0xca } ++ [_]u8{0} ** 24;
    var hashed: [32]u8 = undefined;
    try hashTreeRoot([2]u32, [_]u32{ 0xdeadbeef, 0xcafecafe }, &hashed, std.testing.allocator);
    try expect(std.mem.eql(u8, hashed[0..], expected[0..]));
}

test "calculate root hash of an array of three Bitvector[128]" {
    const deserialized: [3][128]bool = [3][128]bool{ a_bits, b_bits, c_bits };
    var hashed: [32]u8 = undefined;
    try hashTreeRoot(@TypeOf(deserialized), deserialized, &hashed, std.testing.allocator);

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

    try expect(std.mem.eql(u8, hashed[0..], expected[0..]));
}

test "calculate the root hash of an array of five Bitvector[128]" {
    const deserialized = [5][128]bool{ a_bits, b_bits, c_bits, d_bits, e_bits };
    var hashed: [32]u8 = undefined;
    try hashTreeRoot(@TypeOf(deserialized), deserialized, &hashed, std.testing.allocator);

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

    try expect(std.mem.eql(u8, hashed[0..], expected[0..]));
}

const Fork = struct {
    previous_version: [4]u8,
    current_version: [4]u8,
    epoch: u64,
};

test "calculate the root hash of a structure" {
    var hashed: [32]u8 = undefined;
    const fork = Fork{
        .previous_version = [_]u8{ 0x9c, 0xe2, 0x5d, 0x26 },
        .current_version = [_]u8{ 0x36, 0x90, 0x55, 0x93 },
        .epoch = 3,
    };
    var expected: [32]u8 = undefined;
    _ = try std.fmt.hexToBytes(expected[0..], "58316a908701d3660123f0b8cb7839abdd961f71d92993d34e4f480fbec687d9");
    try hashTreeRoot(Fork, fork, &hashed, std.testing.allocator);
    try expect(std.mem.eql(u8, hashed[0..], expected[0..]));
}

test "calculate the root hash of an Optional" {
    var hashed: [32]u8 = undefined;
    var payload: [64]u8 = undefined;
    const v: ?u32 = null;
    const u: ?u32 = 0xdeadbeef;
    var expected: [32]u8 = undefined;

    _ = try std.fmt.hexToBytes(payload[0..], "00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000");
    sha256.hash(payload[0..], expected[0..], sha256.Options{});
    try hashTreeRoot(?u32, v, &hashed, std.testing.allocator);
    try expect(std.mem.eql(u8, hashed[0..], expected[0..]));

    _ = try std.fmt.hexToBytes(payload[0..], "efbeadde000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000");
    sha256.hash(payload[0..], expected[0..], sha256.Options{});
    try hashTreeRoot(?u32, u, &hashed, std.testing.allocator);
    try expect(std.mem.eql(u8, hashed[0..], expected[0..]));
}

test "calculate the root hash of an union" {
    const Payload = union(enum) {
        int: u64,
        boolean: bool,
    };
    var out: [32]u8 = undefined;
    var payload: [64]u8 = undefined;
    _ = try std.fmt.hexToBytes(payload[0..], "d2040000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000");
    var exp1: [32]u8 = undefined;
    sha256.hash(payload[0..], exp1[0..], sha256.Options{});
    try hashTreeRoot(Payload, Payload{ .int = 1234 }, &out, std.testing.allocator);
    try expect(std.mem.eql(u8, out[0..], exp1[0..]));

    var exp2: [32]u8 = undefined;
    _ = try std.fmt.hexToBytes(payload[0..], "01000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000");
    sha256.hash(payload[0..], exp2[0..], sha256.Options{});
    try hashTreeRoot(Payload, Payload{ .boolean = true }, &out, std.testing.allocator);
    try expect(std.mem.eql(u8, out[0..], exp2[0..]));
}

test "stable containers" {
    var array_list = std.ArrayList(u8).init(std.testing.allocator);
    defer array_list.deinit();
    const Payload = struct {
        a: ?u8 = null,
        b: ?u32 = null,
        reserved: StableContainerFiller(32),
    };
    const payload = Payload{
        .a = 8,
        .reserved = .{},
    };
    try serialize(Payload, payload, &array_list);
    var deser_payload: Payload = undefined;
    try deserialize(Payload, array_list.items, &deser_payload);
    // basic container
    const Shape1 = struct {
        side: ?u16,
        color: ?u8,
        radius: ?u16,
        reserved: StableContainerFiller(4),
    };

    // basic container with different depth
    const Shape2 = struct {
        side: ?u16,
        color: ?u8,
        radius: ?u16,
        reserved: StableContainerFiller(8),
    };

    // basic container with variable fields
    const Shape3 = struct {
        side: ?u16,
        colors: ?[]const u8,
        radius: ?u16,
        reserved: StableContainerFiller(8),
    };

    const stable_container_shape1_tests = [_]struct {
        value: Shape1,
        serialized: []const u8,
        hash_tree_root: []const u8,
    }{
        .{ .value = Shape1{ .side = 0x42, .color = 1, .radius = 0x42, .reserved = .{} }, .serialized = "074200014200", .hash_tree_root = "37b28eab19bc3e246e55d2e2b2027479454c27ee006d92d4847c84893a162e6d" },
        .{ .value = Shape1{ .side = 0x42, .color = 1, .radius = null, .reserved = .{} }, .serialized = "03420001", .hash_tree_root = "bfdb6fda9d02805e640c0f5767b8d1bb9ff4211498a5e2d7c0f36e1b88ce57ff" },
        .{ .value = Shape1{ .side = null, .color = 1, .radius = null, .reserved = .{} }, .serialized = "0201", .hash_tree_root = "522edd7309c0041b8eb6a218d756af558e9cf4c816441ec7e6eef42dfa47bb98" },
        .{ .value = Shape1{ .side = null, .color = 1, .radius = 0x42, .reserved = .{} }, .serialized = "06014200", .hash_tree_root = "f66d2c38c8d2afbd409e86c529dff728e9a4208215ca20ee44e49c3d11e145d8" },
    };

    for (stable_container_shape1_tests) |sct| {
        array_list.clearRetainingCapacity();
        try serialize(@TypeOf(sct.value), sct.value, &array_list);
        const got = try std.fmt.allocPrint(std.testing.allocator, "{}", .{std.fmt.fmtSliceHexLower(array_list.items[0..])});
        defer std.testing.allocator.free(got);
        try std.testing.expect(std.mem.eql(u8, got, sct.serialized));
        // var result: [32]u8 = undefined;
        // array_list.clearRetainingCapacity();
        // try hashTreeRoot(Shape1, sct.value, &result, std.testing.allocator);
        // const got_hash = try std.fmt.allocPrint(std.testing.allocator, "{}", .{std.fmt.fmtSliceHexLower(result[0..])});
        // defer std.testing.allocator.free(got_hash);
        // std.debug.print("{}: {s} {s}\n", .{ i, got_hash, sct.hash_tree_root[0..] });
        // try std.testing.expect(std.mem.eql(u8, got_hash, sct.hash_tree_root));
    }

    const stable_container_shape2_tests = [_]struct {
        value: Shape2,
        serialized: []const u8,
        hash_tree_root: []const u8,
    }{
        .{ .value = Shape2{ .side = 0x42, .color = 1, .radius = 0x42, .reserved = .{} }, .serialized = "074200014200", .hash_tree_root = "0792fb509377ee2ff3b953dd9a88eee11ac7566a8df41c6c67a85bc0b53efa4e" },
        .{ .value = Shape2{ .side = 0x42, .color = 1, .radius = null, .reserved = .{} }, .serialized = "03420001", .hash_tree_root = "ddc7acd38ae9d6d6788c14bd7635aeb1d7694768d7e00e1795bb6d328ec14f28" },
        .{ .value = Shape2{ .side = null, .color = 1, .radius = null, .reserved = .{} }, .serialized = "0201", .hash_tree_root = "9893ecf9b68030ff23c667a5f2e4a76538a8e2ab48fd060a524888a66fb938c9" },
        .{ .value = Shape2{ .side = null, .color = 1, .radius = 0x42, .reserved = .{} }, .serialized = "06014200", .hash_tree_root = "e823471310312d52aa1135d971a3ed72ba041ade3ec5b5077c17a39d73ab17c5" },
    };

    for (stable_container_shape2_tests) |sct| {
        array_list.clearRetainingCapacity();
        try serialize(@TypeOf(sct.value), sct.value, &array_list);
        const got = try std.fmt.allocPrint(std.testing.allocator, "{}", .{std.fmt.fmtSliceHexLower(array_list.items[0..])});
        defer std.testing.allocator.free(got);
        try std.testing.expect(std.mem.eql(u8, got, sct.serialized));
        // var result: [32]u8 = undefined;
        // array_list.clearRetainingCapacity();
        // try hashTreeRoot(Shape2, sct.value, &result, std.testing.allocator);
        // const got_hash = try std.fmt.allocPrint(std.testing.allocator, "{}", .{std.fmt.fmtSliceHexLower(result[0..])});
        // defer std.testing.allocator.free(got_hash);
        // std.debug.print("{}: {s} {s}\n", .{ i, got_hash, sct.hash_tree_root[0..] });
        // try std.testing.expect(std.mem.eql(u8, got_hash, sct.hash_tree_root));
    }

    const stable_container_shape3_tests = [_]struct {
        value: Shape3,
        serialized: []const u8,
        hash_tree_root: []const u8,
    }{
        .{ .value = Shape3{ .side = 0x42, .colors = &[_]u8{ 1, 2 }, .radius = 0x42, .reserved = .{} }, .serialized = "0742000800000042000102", .hash_tree_root = "1093b0f1d88b1b2b458196fa860e0df7a7dc1837fe804b95d664279635cb302f" },
        .{ .value = Shape3{ .side = 0x42, .colors = null, .radius = null, .reserved = .{} }, .serialized = "014200", .hash_tree_root = "28df3f1c3eebd92504401b155c5cfe2f01c0604889e46ed3d22a3091dde1371f" },
        .{ .value = Shape3{ .side = null, .colors = &[_]u8{ 1, 2 }, .radius = null, .reserved = .{} }, .serialized = "02040000000102", .hash_tree_root = "659638368467b2c052ca698fcb65902e9b42ce8e94e1f794dd5296ceac2dec3e" },
        .{ .value = Shape3{ .side = null, .colors = null, .radius = 0x42, .reserved = .{} }, .serialized = "044200", .hash_tree_root = "d585dd0561c718bf4c29e4c1bd7d4efd4a5fe3c45942a7f778acb78fd0b2a4d2" },
        .{ .value = Shape3{ .side = null, .colors = &[_]u8{ 1, 2 }, .radius = 0x42, .reserved = .{} }, .serialized = "060600000042000102", .hash_tree_root = "00fc0cecc200a415a07372d5d5b8bc7ce49f52504ed3da0336f80a26d811c7bf" },
    };

    for (stable_container_shape3_tests) |sct| {
        array_list.clearRetainingCapacity();
        try serialize(@TypeOf(sct.value), sct.value, &array_list);
        const got = try std.fmt.allocPrint(std.testing.allocator, "{}", .{std.fmt.fmtSliceHexLower(array_list.items[0..])});
        defer std.testing.allocator.free(got);
        try std.testing.expect(std.mem.eql(u8, got, sct.serialized));
        // var result: [32]u8 = undefined;
        // array_list.clearRetainingCapacity();
        // try hashTreeRoot(Shape3, sct.value, &result, std.testing.allocator);
        // const got_hash = try std.fmt.allocPrint(std.testing.allocator, "{}", .{std.fmt.fmtSliceHexLower(result[0..])});
        // defer std.testing.allocator.free(got_hash);
        // std.debug.print("{}: {s} {s}\n", .{ i, got_hash, sct.hash_tree_root[0..] });
        // try std.testing.expect(std.mem.eql(u8, got_hash, sct.hash_tree_root));

        var shape3: Shape3 = undefined;
        try deserialize(Shape3, array_list.items, &shape3);
        try std.testing.expectEqualDeep(shape3, sct.value);
    }
}
