const main = @import("./main.zig");
const serialize = main.serialize;
const deserialize = main.deserialize;
const chunk_count = main.chunk_count;
const std = @import("std");
const ArrayList = std.ArrayList;
const expect = std.testing.expect;

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

test "chunk count of basic types" {
    expect(chunk_count(bool, false) == 1);
    expect(chunk_count(bool, true) == 1);
    expect(chunk_count(u8, 1) == 1);
    expect(chunk_count(u16, 1) == 1);
    expect(chunk_count(u32, 1) == 1);
    expect(chunk_count(u64, 1) == 1);
}

test "chunk count of Bitvector[N]" {
    const data7 = [_]bool{ true, false, true, true, false, false, false };
    const data12 = [_]bool{ true, false, true, true, false, false, false, true, false, true, false, true };
    comptime var data384: [384]bool = undefined;
    comptime {
        var i = 0;
        while (i < data384.len) : (i += 1) {
            data384[i] = i % 2 == 0;
        }
    }

    expect(chunk_count([7]bool, data7) == 1);
    expect(chunk_count([12]bool, data12) == 1);
    expect(chunk_count([384]bool, data384) == 2);
}

test "chunk count of Vector[B, N]" {
    comptime var data: [17]u32 = undefined;
    comptime {
        var i = 0;
        while (i < data.len) : (i += 1) {
            data[i] = @as(u32, i);
        }
    }

    expect(chunk_count([17]u32, data) == 3);
}

test "chunk count of a struct" {
    expect(chunk_count(Pastry, pastries[0]) == 2);
}

test "chunk count of a Vector[C, N]" {
    expect(chunk_count([2]Pastry, pastries) == 2);
}
