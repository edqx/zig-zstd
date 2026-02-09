const std = @import("std");
const c = @import("c");

pub const DEFAULT_COMPRESSION_LEVEL = 3;
pub const MIN_COMPRESSION_LEVEL = -131072;
pub const MAX_COMPRESSION_LEVEL = 22;

// Code based on https://github.com/alichraghi/zstd.zig/blob/ddd1fe82a5157bb65bc815a552bbfb01bb502acf/src/error.zig#L3
pub const Error = error{
    Generic,
    UnknownPrefix,
    UnsupportedVersion,
    UnsupportedFrameParameter,
    TooLargeFrameParameterWindow,
    CorruptionDetected,
    WrongChecksum,
    CorruptedDictionary,
    WrongDictionary,
    DictionaryCreationFailed,
    UnsupportedParameter,
    OutOfBoundsParameter,
    TooLargeTableLog,
    TooLargeMaxSymbolValue,
    TooSmallMaxSymbolValue,
    WrongStage,
    InitMissing,
    OutOfMemory,
    TooSmallWorkspace,
    TooSmallDestSize,
    WrongSrcSize,
    NullDestBuffer,
    NoForwardProgressDestFull,
    NoForwardProgressInputEmpty,
    TooLargeFrameIndex,
    SeekableIO,
    WrongDestBuffer,
    WrongSrcBuffer,
    SequenceProducerFailed,
    InvalidExternalSequences,
    MaxCode,
    UnknownError,
};

pub inline fn isError(code: usize) bool {
    return c.ZSTD_isError(code) != 0;
}

pub fn checkError(code: usize) Error!usize {
    if (isError(code))
        switch (c.ZSTD_getErrorCode(code)) {
            1 => return error.Generic,
            10 => return error.UnknownPrefix,
            12 => return error.UnsupportedVersion,
            14 => return error.UnsupportedFrameParameter,
            16 => return error.TooLargeFrameParameterWindow,
            20 => return error.CorruptionDetected,
            22 => return error.WrongChecksum,
            30 => return error.CorruptedDictionary,
            32 => return error.WrongDictionary,
            34 => return error.DictionaryCreationFailed,
            40 => return error.UnsupportedParameter,
            42 => return error.OutOfBoundsParameter,
            44 => return error.TooLargeTableLog,
            46 => return error.TooLargeMaxSymbolValue,
            48 => return error.TooSmallMaxSymbolValue,
            60 => return error.WrongStage,
            62 => return error.InitMissing,
            64 => return error.OutOfMemory,
            66 => return error.TooSmallWorkspace,
            70 => return error.TooSmallDestSize,
            72 => return error.WrongSrcSize,
            74 => return error.NullDestBuffer,
            80 => return error.NoForwardProgressDestFull,
            82 => return error.NoForwardProgressInputEmpty,
            // following error codes are __NOT STABLE__, they can be removed or changed in future versions
            100 => return error.TooLargeFrameIndex,
            102 => return error.SeekableIO,
            104 => return error.WrongDestBuffer,
            105 => return error.WrongSrcBuffer,
            106 => return error.SequenceProducerFailed,
            107 => return error.InvalidExternalSequences,
            120 => return error.MaxCode,
            else => return error.UnknownError,
        };
    return code;
}

pub const Compress = struct {
    inner: *c.ZSTD_CStream,

    source: *std.Io.Reader,
    reader: std.Io.Reader,

    pub fn init(source: *std.Io.Reader, level: i32) Error!Compress {
        const c_stream = c.ZSTD_createCStream();
        if (c_stream == null) return error.OutOfMemory;
        
        _ = try checkError(c.ZSTD_initCStream(c_stream, level));

        return .{
            .inner = c_stream.?,
            .source = source,
            .reader = .{
                .buffer = &.{},
                .seek = 0,
                .end = 0,
                .vtable = &.{
                    .stream = &stream,
                },
            },
        };
    }
    
    pub fn deinit(compress: *Compress) void {
        _ = c.ZSTD_freeCStream(compress.inner);
        compress.* = undefined;
    }
    
    pub fn stream(reader: *std.Io.Reader, writer: *std.Io.Writer, limit: std.Io.Limit) std.Io.Reader.StreamError!usize {
        const compress: *Compress = @fieldParentPtr("reader", reader);

        compress.source.fill(1) catch |e| switch (e) {
            error.EndOfStream => {
                const dest = limit.slice(try writer.writableSliceGreedy(1));
        
                var out_buffer: c.ZSTD_outBuffer_s = .{
                    .dst = dest.ptr,
                    .size = dest.len,
                    .pos = 0,
                };
        
                _ = checkError(c.ZSTD_endStream(compress.inner, &out_buffer)) catch return error.ReadFailed;
                
                writer.advance(out_buffer.pos);
                return error.EndOfStream;
            },
            else => return e,
        };
        
        const src = compress.source.buffered();
        
        var in_buffer: c.ZSTD_inBuffer_s = .{
            .src = src.ptr,
            .size = src.len,
            .pos = 0,
        };
        
        const dest = limit.slice(try writer.writableSliceGreedy(1));
        
        var out_buffer: c.ZSTD_outBuffer_s = .{
            .dst = dest.ptr,
            .size = dest.len,
            .pos = 0,
        };
        
        
        _ = checkError(c.ZSTD_compressStream(compress.inner, &out_buffer, &in_buffer)) catch return error.ReadFailed;
    
        compress.source.toss(in_buffer.pos);
        writer.advance(out_buffer.pos);
        return out_buffer.pos;
    }
};

test Compress {
    const gpa = std.testing.allocator;

    const data = "BARNEY BARNEY BARNEY BARNEY";
    var reader: std.Io.Reader = .fixed(data);

    var compress: Compress = try .init(&reader, 1);
    defer compress.deinit();
    
    const compressed = try compress.reader.allocRemaining(gpa, .unlimited);
    defer gpa.free(compressed);
    
    try std.testing.expectEqualSlices(u8, &.{ 40, 181, 47, 253, 0, 72, 109, 0, 0, 56, 66, 65, 82, 78, 69, 89, 32, 1, 0, 162, 139, 17 }, compressed);
}