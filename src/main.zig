//! This module provides functions for serializing and deserializing
//! data structures with the SSZ method.

const std = @import("std");
const ArrayList = std.ArrayList;
const builtin = std.builtin;

/// Number of bytes per chunk.
const BYTES_PER_CHUNK = 32;

/// Number of bytes per serialized length offset.
const BYTES_PER_LENGTH_OFFSET = 4;

// Determine the serialized size of an object so that
// the code serializing of variable-size objects can
// determine the offset to the next object.
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
fn is_fixed_size_object(comptime T: type) !bool {
    const info = @typeInfo(T);
    switch (info) {
        .Bool, .Int, .Null => return true,
        .Array => return false,
        .Struct => inline for (info.Struct.fields) |field| {
            if (!try is_fixed_size_object(field.field_type)) {
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
        .Array => {
            // Bitvector[N] or vector?
            if (info.Array.child == bool) {
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
            } else {
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
                    const offset = [_]u8{ 0, 0, 0, 0 };
                    for (data) |_| {
                        _ = try l.writer().write(offset[0..4]);
                    }

                    // Now serialize one item after the other
                    // and update the offset list with its location.
                    for (data) |item, index| {
                        std.mem.writeIntLittle(u32, l.items[start .. start + 4][0..4], @truncate(u32, l.items.len));
                        _ = try serialize(info.Array.child, item, l);
                        start += 4;
                    }
                }
            }
        },
        .Bool => {
            if (data) {
                try l.append(1);
            } else {
                try l.append(0);
            }
        },
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
        // Nothing to be added
        .Null => {},
        .Optional => if (data != null) try serialize(info.Optional.child, data.?, l),
        .Union => {
            if (info.Union.tag_type == null) {
                return error.UnionIsNotTagged;
            }
            inline for (info.Union.fields) |f, index| {
                if (@enumToInt(data) == index) {
                    try serialize(u32, index, l);
                    try serialize(f.field_type, @field(data, f.name), l);
                    return;
                }
            }
        },
        else => {
            return error.UnknownType;
        },
    }
}

/// Takes a byte array containing the serialized payload of type `T` (with
/// possible trailing data) and deserializes it into the `T` object pointed
/// at by `out`.
pub fn deserialize(comptime T: type, serialized: []const u8, out: *T) !void {
    const info = @typeInfo(T);
    switch (info) {
        .Array => {
            // Bitvector[N] or regular vector?
            if (info.Array.child == bool) {
                for (serialized) |byte, bindex| {
                    var i = @as(u8, 0);
                    var b = byte;
                    while (bindex * 8 + i < out.len and i < 8) : (i += 1) {
                        out[bindex * 8 + i] = b & 1 == 1;
                        b >>= 1;
                    }
                }
            } else {
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
                    const indices = std.mem.bytesAsSlice(u32, serialized[0 .. size * 4]);
                    var i = @as(usize, 0);
                    while (i < size) : (i += 1) {
                        const end = if (i < size - 1) indices[i + 1] else serialized.len;
                        const start = indices[i];
                        if (start >= serialized.len or end > serialized.len) {
                            return error.IndexOutOfBounds;
                        }
                        try deserialize(U, serialized[start..end], &out[i]);
                    }
                }
            }
        },
        .Bool => out.* = (serialized[0] == 1),
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
        .Optional => if (serialized.len != 0) {
            var x: info.Optional.child = undefined;
            try deserialize(info.Optional.child, serialized, &x);
            out.* = x;
        } else {
            out.* = null;
        },
        // Data is not copied in this function, copy is therefore
        // the responsibility of the caller.
        .Pointer => out.* = serialized[0..],
        .Struct => {
            // Calculate the number of variable fields in the
            // struct.
            comptime var n_var_fields = 0;
            comptime {
                for (info.Struct.fields) |field| {
                    switch (@typeInfo(field.field_type)) {
                        .Int, .Bool => {},
                        else => n_var_fields += 1,
                    }
                }
            }

            var indices: [n_var_fields]u32 = undefined;

            // First pass, read the value of each fixed-size field,
            // and write down the start offset of each variable-sized
            // field.
            comptime var i = 0;
            inline for (info.Struct.fields) |field, field_index| {
                switch (@typeInfo(field.field_type)) {
                    .Bool, .Int => {
                        // Direct deserialize
                        try deserialize(field.field_type, serialized[i .. i + @sizeOf(field.field_type)], &@field(out.*, field.name));
                        i += @sizeOf(field.field_type);
                    },
                    else => {
                        try deserialize(u32, serialized[i .. i + 4], &indices[field_index]);
                        i += 4;
                    },
                }
            }

            // Second pass, deserialize each variable-sized value
            // now that their offset is known.
            comptime var last_index = 0;
            inline for (info.Struct.fields) |field| {
                switch (@typeInfo(field.field_type)) {
                    .Bool, .Int => {}, // covered by the previous pass
                    else => {
                        const end = if (last_index == indices.len - 1) serialized.len else indices[last_index + 1];
                        try deserialize(field.field_type, serialized[indices[last_index]..end], &@field(out.*, field.name));
                        last_index += 1;
                    },
                }
            }
        },
        .Union => {
            // Read the type index
            var union_index: u32 = undefined;
            try deserialize(u32, serialized, &union_index);

            // Use the index to figure out which type must
            // be deserialized.
            inline for (info.Union.fields) |field, index| {
                if (index == union_index) {
                    // &@field(out.*, field.name) can not be used directly,
                    // because this field type hasn't been activated at this
                    // stage.
                    var data: field.field_type = undefined;
                    try deserialize(field.field_type, serialized[4..], &data);
                    out.* = @unionInit(T, field.name, data);
                }
            }
        },
        else => return error.NotImplemented,
    }
}

/// Calculates the number of leaves needed for the merkelization
/// of this type.
pub fn chunk_count(comptime T: type, data: T) usize {
    const info = @typeInfo(T);
    switch (info) {
        .Int, .Bool => return 1,
        .Pointer => return chunk_count(info.Pointer.child, data.*),
        // the chunk size of an array depends on its type
        .Array => switch (@typeInfo(info.Array.child)) {
            // Bitvector[N]
            .Bool => return (data.len + 255) / 256,
            // Vector[B,N]
            .Int => return (data.len * @sizeOf(info.Array.child) + 31) / 32,
            // Vecotr[C,N]
            else => return data.len,
        },
        .Struct => return info.Struct.fields.len,
        else => return error.NotSupported,
    }
}




    }
}
