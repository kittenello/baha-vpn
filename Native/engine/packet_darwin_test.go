//go:build darwin

package engine

import (
    "encoding/binary"
    "fmt"
    "net"
    "os"
    "testing"
    "time"
    "golang.org/x/sys/unix"
)

// Proves that the unpatched official TUN accepts our datagram/AF framing and returns a real packet.
func TestPacketFlowUDPToLoopbackAndRestart(t *testing.T) {
    for attempt := 0; attempt < 2; attempt++ {
        echo, err := net.ListenPacket("udp4", "127.0.0.1:0")
        if err != nil { t.Fatal(err) }
        port := echo.LocalAddr().(*net.UDPAddr).Port
        go func() { buffer := make([]byte, 1500); n, address, err := echo.ReadFrom(buffer); if err == nil { _, _ = echo.WriteTo(buffer[:n], address) } }()
        pair, err := unix.Socketpair(unix.AF_UNIX, unix.SOCK_DGRAM, 0)
        if err != nil { t.Fatal(err) }
        _ = unix.SetNonblock(pair[1], true)
        bridge := os.NewFile(uintptr(pair[1]), "packet-flow")
        config := `{"log":{"loglevel":"none"},"inbounds":[{"protocol":"tun","settings":{"name":"utun","MTU":1360}}],"outbounds":[{"protocol":"freedom","settings":{}}]}`
        if err := Start(config, pair[0], ""); err != nil { t.Fatal(err) }
        packet := make([]byte, 4+20+8+4)
        binary.BigEndian.PutUint32(packet[:4], uint32(unix.AF_INET))
        ip := packet[4:24]
        ip[0] = 0x45; ip[8] = 64; ip[9] = 17
        binary.BigEndian.PutUint16(ip[2:4], uint16(len(packet)-4))
        copy(ip[12:16], net.ParseIP("198.18.0.2").To4())
        copy(ip[16:20], net.ParseIP("127.0.0.1").To4())
        var sum uint32
        for offset := 0; offset < 20; offset += 2 { sum += uint32(binary.BigEndian.Uint16(ip[offset:offset+2])) }
        for sum >> 16 != 0 { sum = (sum & 65535) + (sum >> 16) }
        binary.BigEndian.PutUint16(ip[10:12], ^uint16(sum))
        udp := packet[24:]
        binary.BigEndian.PutUint16(udp[:2], 54321)
        binary.BigEndian.PutUint16(udp[2:4], uint16(port))
        binary.BigEndian.PutUint16(udp[4:6], uint16(len(udp)))
        copy(udp[8:], "baha")
        if _, err := bridge.Write(packet); err != nil { t.Fatal(err) }
        _ = bridge.SetReadDeadline(time.Now().Add(8 * time.Second))
        buffer := make([]byte, 1500)
        n, err := bridge.Read(buffer)
        Stop()
        _ = bridge.Close(); _ = unix.Close(pair[0]); _ = echo.Close()
        if err != nil { t.Fatal(fmt.Errorf("packet did not return through the official TUN: %w", err)) }
        if n < 32 || string(buffer[n-4:n]) != "baha" { t.Fatal("bad returned UDP payload") }
    }
}
