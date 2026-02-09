# zig-zstd

This is a fork of [zig-zstd](https://github.com/Scythe-Technology/zig-zstd) to add a compression stream
reader/writer.

It also uses my own fork of [zstd](https://github.com/edqx/zstd) which removes the tests, since Zig's package
manager complains on Windows when pulling from git repositories with symlinks.
