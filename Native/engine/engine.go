package engine

import (
    "bytes"
    "encoding/json"
    "os"
    "runtime/debug"
    "strconv"
    "sync"

    "github.com/xtls/xray-core/core"
    "golang.org/x/sys/unix"
    _ "github.com/xtls/xray-core/main/distro/all"
    _ "github.com/xtls/xray-core/proxy/hysteria"
    _ "github.com/xtls/xray-core/proxy/shadowsocks_2022"
    _ "github.com/xtls/xray-core/proxy/tun"
    _ "github.com/xtls/xray-core/transport/internet/hysteria"
)

var mu sync.Mutex
var instance *core.Instance
var activeFD = -1

func Config(text string) (*core.Config, error) {
    return core.LoadConfig("json", bytes.NewReader([]byte(text)))
}

func Start(text string, fd int, assets string) error {
    mu.Lock()
    defer mu.Unlock()
    if instance != nil { if activeFD >= 0 { _ = unix.Shutdown(activeFD, unix.SHUT_RDWR) }; _ = instance.Close(); instance = nil }
    debug.SetMemoryLimit(32 * 1024 * 1024)
    debug.SetGCPercent(20)
    if err := os.Setenv("XRAY_TUN_FD", strconv.Itoa(fd)); err != nil { return err }
    if assets != "" { _ = os.Setenv("XRAY_LOCATION_ASSET", assets) }
    var object map[string]any
    if err := json.Unmarshal([]byte(text), &object); err != nil { return err }
    object["log"] = map[string]any{"loglevel": "none"}
    serialized, err := json.Marshal(object)
    if err != nil { return err }
    cfg, err := Config(string(serialized))
    if err != nil { return err }
    next, err := core.New(cfg)
    if err != nil { return err }
    if err = next.Start(); err != nil { _ = next.Close(); return err }
    instance = next
    activeFD = fd
    return nil
}

func Stop() {
    mu.Lock()
    defer mu.Unlock()
    if instance != nil { if activeFD >= 0 { _ = unix.Shutdown(activeFD, unix.SHUT_RDWR) }; _ = instance.Close(); instance = nil }
    activeFD = -1
    _ = os.Unsetenv("XRAY_TUN_FD")
    debug.FreeOSMemory()
}
