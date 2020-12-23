//! This module provides functions for serializing and deserializing
//! data structures with the SSZ method.

const std = @import("std");
const ArrayList = std.ArrayList;
const expect = std.testing.expect;
const builtin = std.builtin;

fn serialized_size(comptime T: type, data: T) !usize {
    const info = @typeInfo(T);
    return switch (info) {
        .Array => data.len,
        .Pointer => switch (info.Pointer.size) {
            .Slice => data.len,
            else => serialized_size(info.Pointer.child, data.*),
        },
        .Optional => if (data == null)
            @as(usize, 0)
        else
            serialized_size(info.Optional.child, data.?),
        else => error.NoSerializedSizeAvailable,
    };
}

/// Returns true if an object is of fixed size
fn is_fixed_size_object(comptime T : type) !bool {
    const info = @typeInfo(T);
    switch (info) {
        .Bool, .Int, .Null => return true,
        .Array => return false,
        .Struct => inline for (info.Struct.fields) |field| {
            if (! try is_fixed_size_object(field.field_type)) {
                return false;
            }
        },
        .Pointer => switch (info.Pointer.size) {
            .Many, .Slice, .C => return false,
            .One => return is_fixed_size_object(info.Pointer.child),
        },
        else => return error.UnknownType,
    }
    return true;
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
                    .Big => @truncate(u8, data >> (8 * (N - i - 1))),
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
                    // If the item type is fixed-size, serialize inline,
                    // otherwise, create an array of offsets and then
                    // serialize each object afterwards.
                    if (try is_fixed_size_object(info.Array.child)) {
                        for (data) |item| {
                            try serialize(info.Array.child, item, l);
                        }
                    } else {
                        // Size of the buffer before anything is
                        // written to it.
                        var start = l.items.len;

                        // Reserve the space for the offset
                        const offset = [_]u8{0, 0, 0, 0};
                        for (data) |_| {
                            _ = try l.writer().write(offset[0..4]);
                        }

                        // Now serialize one item after the other
                        // and update the offset list with its location.
                        for (data) |item,index| {
                            std.mem.writeIntLittle(u32, l.items[start..start+4][0..4], @truncate(u32, l.items.len));
                            _ = try serialize(info.Array.child, item, l);
                            start += 4;
                        }
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

test "serializes an array of structures" { 
    var list = ArrayList(u8).init(std.testing.allocator);
    defer list.deinit();
    const exp = [_]u8{8,0,0,0,23,0,0,0,6,0,0,0,20,0,99,114,111,105,115,115,97,110,116,6,0,0,0,244,1,72,101,114,114,101,110,116,111,114,116,101};

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

pub fn deserialize(comptime T: type, serialized: []const u8, out: *T) !void {
    const info = @typeInfo(T);
    switch (info) {
        .Int => {
            const N = @sizeOf(T);
            comptime var i: usize = 0;
            out.* = @as(T, 0);
            inline while (i < N) : (i += 1) {
                // if the integer takes more than one byte, then
                // shift the result by one byte and OR the next
                // byte in the sequence.
                if (@sizeOf(T) > 1) {
                    out.* <<= 8;
                }
                out.* |= switch (builtin.endian) {
                    .Big => @as(T, serialized[i]),
                    .Little => @as(T, serialized[N - i - 1]),
                };
            }
        },
        .Bool => out.* = (serialized[0] == 1),
        .Array => {
            // Bitvector[N] or regular vector?
            switch (@typeInfo(info.Array.child)) {
                .Bool => {
                    for (serialized) |byte, bindex| {
                        var i = @as(u8, 0);
                        var b = byte;
                        while (bindex * 8 + i < out.len and i < 8) : (i += 1) {
                            out[bindex * 8 + i] = b & 1 == 1;
                            b >>= 1;
                        }
                    }
                },
                else => {
                    comptime const U = info.Array.child;
                    if (try is_fixed_size_object(U)) {
                        comptime var i = 0;
                        comptime const pitch = @sizeOf(U);
                        inline while (i < out.len) : (i += pitch) {
                            try deserialize(U, serialized[i * pitch .. (i + 1) * pitch], &out[i]);
                        }
                    } else {
                        // first variable index is also the size of the list
                        // of indices. Recast that list as a []const u32.
                        const size = std.mem.readIntLittle(u32, serialized[0..4]) / @sizeOf(u32);
                        const indices = std.mem.bytesAsSlice(u32, serialized[0..size*4]);
                        var i = @as(usize, 0);
                        while (i < size) : (i += 1) {
                            const end = if (i < size - 1) indices[i+1] else serialized.len;
                            const start = indices[i];
                            if (start >= serialized.len or end > serialized.len) {
                                return error.IndexOutOfBounds;
                            }
                            try deserialize(U, serialized[start..end], &out[i]);
                        }
                    }
                },
            }
        },
        .Pointer => {
            // TODO allocate and copy the data.
            out.* = serialized[0..serialized.len];
        },
        .Struct => {
            // Calculate the number of variable fields in the
            // struct.
            comptime var n_var_fields = 0;
             comptime {
                for (info.Struct.fields) |field| {
                    switch (@typeInfo(field.field_type)) {
                        .Int, .Bool => {},
                        else =>n_var_fields += 1,
                    }
                }
            }

            var indices : [n_var_fields]u32 = undefined;

            // First pass, read the value of each fixed-size field,
            // and write down the start offset of each variable-sized
            // field.
            comptime var i = 0;
            inline for (info.Struct.fields) |field,field_index| {
                switch (@typeInfo(field.field_type)) {
                    .Bool, .Int => {
                        // Direct deserialize
                        try deserialize(field.field_type, serialized[i..i+@sizeOf(field.field_type)], &@field(out.*, field.name));
                        i += @sizeOf(field.field_type);
                    },
                    else => { 
                        try deserialize(u32, serialized[i..i+4], &indices[field_index]);
                        i += 4;
                    },
                }
            }

            // Second pass, deserialize each variable-sized value
            // now that their offset is known.
            comptime var last_index = 0;
            inline for (info.Struct.fields) |field| {
                switch (@typeInfo(field.field_type)) {
                    .Bool, .Int => {},  // covered by the previous pass
                    else => {
                        const end = if (last_index == indices.len-1) serialized.len else indices[last_index+1];
                        try deserialize(field.field_type, serialized[indices[last_index]..end], &@field(out.*, field.name));
                        last_index += 1;
                    }
                }
            }
        },
        else => return error.NotImplemented,
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
    var out = [_]bool{false, false, false, false, false, false, false};
    const serialized_data = [_]u8{0b00001101};
    try deserialize([7]bool, serialized_data[0..1], &out);
    comptime var i = 0;
    inline while (i<7) : (i += 1) {
        expect(out[i] == exp[i]);
    }
}

test "deserializes a string" {
    const exp = "croissants";
    
    var list = ArrayList(u8).init(std.testing.allocator);
    defer list.deinit();
    const serialized = try serialize([]const u8, exp, &list);

    var got : []const u8 = undefined;

    try deserialize([]const u8, list.items, &got);
    expect(std.mem.eql(u8, exp, got));
}

const Pastry = struct {
    name : []const u8,
    weight : u16,
};

const pastries = [_]Pastry{
    Pastry{
        .name = "croissant",
        .weight = 20
    },
    Pastry{
        .name = "Herrentorte",
        .weight = 500,
    },
};

test "deserializes a structure" {
    var out = Pastry { .name = "", .weight = 0};
    var list = ArrayList(u8).init(std.testing.allocator);
    defer list.deinit();

    try serialize(Pastry, pastries[0], &list);
    try deserialize(Pastry, list.items, &out);

    expect(pastries[0].weight == out.weight);
    expect(std.mem.eql(u8, pastries[0].name, out.name));
}

test "deserializes a Vector[N]" {
    var out : [2]Pastry = undefined;
    var list = ArrayList(u8).init(std.testing.allocator);
    defer list.deinit();

    try serialize([2]Pastry, pastries, &list);
    try deserialize(@TypeOf(pastries), list.items, &out);
    comptime var i = 0;
    inline while (i<pastries.len) : (i += 1) {
        expect(out[i].weight == pastries[i].weight);
        expect(std.mem.eql(u8, pastries[i].name, out[i].name));
    }
}

    }
}
