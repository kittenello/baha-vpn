package main

/*
#include <stdlib.h>
*/
import "C"
import (
    "unsafe"
    "github.com/kittenello/baha-vpn/native/engine"
)

//export BahaStart
func BahaStart(config *C.char, fd C.int, assets *C.char) C.int {
    // Do not return core errors containing credentials to the UI or the logs.
    if err := engine.Start(C.GoString(config), int(fd), C.GoString(assets)); err != nil { return 1 }
    return 0
}

//export BahaStop
func BahaStop() { engine.Stop() }

//export BahaValidate
func BahaValidate(config *C.char) C.int {
    if _, err := engine.Config(C.GoString(config)); err != nil { return 1 }
    return 0
}

//export BahaFree
func BahaFree(pointer unsafe.Pointer) { C.free(pointer) }

func main() {}
