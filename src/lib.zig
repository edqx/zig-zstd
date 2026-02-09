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