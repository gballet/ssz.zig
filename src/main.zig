const std = @import("std");
const ArrayList = std.ArrayList;
const expect = std.testing.expect;
const builtin = std.builtin;

fn serialize(comptime T: type, data: T, l: *ArrayList(u8)) !void {
    const info = @typeInfo(T);
    switch (info) {
        .Int => {
            const N = @sizeOf(T);
                    comptime var i: usize = 0;
                    inline while (i < N) : (i += 1) {
                        const byte: u8 = @truncate(u8, data >> (8 * i));
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
        .Struct => {
            // Second pass: intertwine fixed fields and variables offsets
            comptime var var_acc = 0; // variable part size accumulator
            inline for (info.Struct.fields) |field| {
                switch (@typeInfo(field.field_type)) {
                    .Int, .Bool => {
                        try serialize(field.field_type, @field(data, field.name), l);
                    },
                    else => {
                        return error.UnknownType;
                    },
                }
            }
        },
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

test "serializes structure without variable parts" {
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
