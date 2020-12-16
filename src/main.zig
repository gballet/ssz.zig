//! This module provides functions for serializing and deserializing
//! data structures with the SSZ method.

const std = @import("std");
const ArrayList = std.ArrayList;
const expect = std.testing.expect;
const builtin = std.builtin;

fn serialized_size(comptime T: type, data: T) !usize {
    const info = @typeInfo(T);
    switch (info) {
        .Array => return data.len,
        .Pointer => {
            switch (info.Pointer.size) {
                .Slice => {
                    return data.len;
                },
                else => {
                    return serialized_size(info.Pointer.child, data.*);
                },
            }
        },
        .Optional => if (data == null)
            return @as(usize, 0)
        else
            return serialized_size(info.Optional.child, data.?),
        else => {
            return error.NoSerializedSizeAvailable;
        },
    }
}

/// Provides the generic serialization of any `data` var to SSZ. The
/// serialization is written to the `ArrayList` `l`.
pub fn serialize(comptime T: type, data: T, l: *ArrayList(u8)) !void {
    const info = @typeInfo(T);
    switch (info) {
        .Int => {
            const N = @sizeOf(T);
            comptime var i: usize = 0;
            inline while (i < N) : (i += 1) {
                const byte: u8 = switch (builtin.endian) {
                    .Big => @truncate(u8, data >> (8 * (N - i))),
                    .Little => @truncate(u8, data >> (8 * i)),
                };
                try l.append(byte);
            }
        },
        .Bool => {
            if (data) {
                try l.append(1);
            } else {
                try l.append(0);
            }
        },
        .Array => {
            // Bitvector[N] or vector?
            switch (@typeInfo(info.Array.child)) {
                .Bool => {
                    var byte: u8 = 0;
                    for (data) |bit, index| {
                        if (bit) {
                            byte |= @as(u8, 1) << @truncate(u3, index);
                        }

                        if (index % 8 == 7) {
                            try l.append(byte);
                            byte = 0;
                        }
                    }

                    // Write the last byte if the length
                    // is not byte-aligned
                    if (data.len % 8 != 0) {
                        try l.append(byte);
                    }
                },
                else => {
                    return error.UnknownType;

                    for (data) |item| {
                        try serialize(info.Array.child, item, l);
                    }
                },
            }
        },
        .Pointer => {
            // Bitlist[N] or list?
            switch (info.Pointer.size) {
                .Slice, .One => {
                    if (@sizeOf(info.Pointer.child) == 1) {
                        _ = try l.writer().write(data);
                    } else {
                        for (data) |item| {
                            try serialize(@TypeOf(item), item, l);
                        }
                    }
                },
                else => return error.UnSupportedPointerType,
            }
        },
        .Struct => {
            // First pass, accumulate the fixed sizes
            comptime var var_start = 0;
            inline for (info.Struct.fields) |field| {
                if (@typeInfo(field.field_type) == .Int or @typeInfo(field.field_type) == .Bool) {
                    var_start += @sizeOf(field.field_type);
                } else {
                    var_start += 4;
                }
            }

            // Second pass: intertwine fixed fields and variables offsets
            var var_acc = @as(usize, var_start); // variable part size accumulator
            inline for (info.Struct.fields) |field| {
                switch (@typeInfo(field.field_type)) {
                    .Int, .Bool => {
                        try serialize(field.field_type, @field(data, field.name), l);
                    },
                    else => {
                        try serialize(u32, @truncate(u32, var_acc), l);
                        var_acc += try serialized_size(field.field_type, @field(data, field.name));
                    },
                }
            }

            // Third pass: add variable fields at the end
            if (var_acc > var_start) {
                inline for (info.Struct.fields) |field| {
                    switch (@typeInfo(field.field_type)) {
                        .Int, .Bool => {
                            // skip fixed-size fields
                        },
                        else => {
                            try serialize(field.field_type, @field(data, field.name), l);
                        },
                    }
                }
            }
        },
        .Null => {
            // Nothing to be added
        },
        .Optional => if (data != null) try serialize(info.Optional.child, data.?, l),
        else => {
            return error.UnknownType;
        },
    }
}

test "serializes uint8" {
    var data: u8 = 0x55;
    const serialized_data = [_]u8{0x55};
    const exp = serialized_data[0..serialized_data.len];

    var list = ArrayList(u8).init(std.testing.allocator);
    defer list.deinit();
    try serialize(u8, data, &list);
    expect(std.mem.eql(u8, list.items, exp));
}

test "serializes uint16" {
    var data: u16 = 0x5566;
    const serialized_data = [_]u8{ 0x66, 0x55 };
    const exp = serialized_data[0..serialized_data.len];

    var list = ArrayList(u8).init(std.testing.allocator);
    defer list.deinit();
    try serialize(u16, data, &list);
    expect(std.mem.eql(u8, list.items, exp));
}

test "serializes uint32" {
    var data: u32 = 0x55667788;
    const serialized_data = [_]u8{ 0x88, 0x77, 0x66, 0x55 };
    const exp = serialized_data[0..serialized_data.len];

    var list = ArrayList(u8).init(std.testing.allocator);
    defer list.deinit();
    try serialize(u32, data, &list);
    expect(std.mem.eql(u8, list.items, exp));
}

test "serializes bool" {
    var data = false;
    var serialized_data = [_]u8{0x00};
    var exp = serialized_data[0..serialized_data.len];

    var list = ArrayList(u8).init(std.testing.allocator);
    defer list.deinit();
    try serialize(bool, data, &list);
    expect(std.mem.eql(u8, list.items, exp));

    data = true;
    serialized_data = [_]u8{0x01};
    exp = serialized_data[0..serialized_data.len];

    var list2 = ArrayList(u8).init(std.testing.allocator);
    defer list2.deinit();
    try serialize(bool, data, &list2);
    expect(std.mem.eql(u8, list2.items, exp));
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
    const expected = serialized[0..serialized.len];

    var list = ArrayList(u8).init(std.testing.allocator);
    defer list.deinit();
    try serialize([]const u16, data[0..data.len], &list);
    expect(std.mem.eql(u8, list.items, expected));
}

test "serializes a structure without variable fields" {
    var data = .{
        .uint8 = @as(u8, 1),
        .uint32 = @as(u32, 3),
        .boolean = true,
    };
    const serialized_data = [_]u8{ 1, 3, 0, 0, 0, 1 };
    const exp = serialized_data[0..serialized_data.len];

    var list = ArrayList(u8).init(std.testing.allocator);
    defer list.deinit();
    try serialize(@TypeOf(data), data, &list);
    expect(std.mem.eql(u8, list.items, exp));
}

test "serializes a structure with variable fields" {
    // Taken from ssz.cr
    const data = .{
        .name = "James",
        .age = @as(u8, 32),
        .company = "DEV Inc.",
    };
    const serialized_data = [_]u8{ 9, 0, 0, 0, 32, 14, 0, 0, 0, 74, 97, 109, 101, 115, 68, 69, 86, 32, 73, 110, 99, 46 };
    const exp = serialized_data[0..serialized_data.len];

    var list = ArrayList(u8).init(std.testing.allocator);
    defer list.deinit();
    try serialize(@TypeOf(data), data, &list);
    expect(std.mem.eql(u8, list.items, exp));
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
    const exp = serialized_data[0..serialized_data.len];

    var list = ArrayList(u8).init(std.testing.allocator);
    defer list.deinit();
    try serialize(@TypeOf(data), data, &list);
    expect(std.mem.eql(u8, list.items, exp));
}

test "serializes an optional object" {
    const null_or_string: ?[]const u8 = null;
    var list = ArrayList(u8).init(std.testing.allocator);
    defer list.deinit();
    try serialize(@TypeOf(null_or_string), null_or_string, &list);
    expect(list.items.len == 0);
}
