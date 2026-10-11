# origin

vendored from https://github.com/dima-u/SwiftyXrayKit at tag `2.0.0`,
commit `3c5405521ae547de110f6ea65df00b1c05f6a0bc`.

the original apache 2.0 license and source copyright notices are retained.
the package manifest uses swift 5 language mode with a swift 6 toolchain to match
this prototype; upstream's test target is omitted because its tests are not vendored.

the binary is upstream's checksum-pinned `LibXray.xcframework`, based on
https://github.com/dima-u/libXray-apple and https://github.com/dima-u/Xray-core-apple.
it patches the official xtls projects for ios socketpair-based tun and memory limits.
this prototype does not claim to use an unmodified official xtls binary.

binary source: https://github.com/dima-u/libXray-apple/tree/v26.3.27-ios
core source: https://github.com/dima-u/Xray-core-apple
upstream xray license: https://github.com/XTLS/Xray-core/blob/main/LICENSE
