#!/usr/bin/env python3
"""
Dart VM Service 性能探针 - 纯 stdlib 实现 (无第三方依赖)
通过 WebSocket JSON-RPC 查询: VM信息 / Isolate / 内存 / CPU
"""
import socket, struct, hashlib, base64, json, time, sys

HOST = "127.0.0.1"
PORT = 38397
PATH = "/lXFNoUWIB3g=/"

def ws_handshake(sock):
    key = base64.b64encode(b"dart_vm_probe_key").decode()
    req = (
        f"GET {PATH} HTTP/1.1\r\n"
        f"Host: {HOST}:{PORT}\r\n"
        f"Upgrade: websocket\r\n"
        f"Connection: Upgrade\r\n"
        f"Sec-WebSocket-Key: {key}\r\n"
        f"Sec-WebSocket-Version: 13\r\n"
        f"\r\n"
    )
    sock.sendall(req.encode())
    resp = b""
    while b"\r\n\r\n" not in resp:
        resp += sock.recv(4096)
    if b"101" not in resp:
        print("WS 握手失败:", resp[:200])
        sys.exit(1)
    print("✅ WebSocket 握手成功")

def ws_send(sock, msg: str):
    data = msg.encode()
    length = len(data)
    mask = b'\x01\x02\x03\x04'
    masked = bytes([data[i] ^ mask[i % 4] for i in range(length)])
    if length <= 125:
        header = bytes([0x81, 0x80 | length]) + mask
    elif length <= 65535:
        header = bytes([0x81, 0xFE]) + struct.pack(">H", length) + mask
    else:
        header = bytes([0x81, 0xFF]) + struct.pack(">Q", length) + mask
    sock.sendall(header + masked)

def ws_recv(sock) -> str:
    def recv_exact(n):
        buf = b""
        while len(buf) < n:
            chunk = sock.recv(n - len(buf))
            if not chunk:
                raise ConnectionError("连接断开")
            buf += chunk
        return buf

    header = recv_exact(2)
    opcode = header[0] & 0x0F
    masked = (header[1] & 0x80) != 0
    length = header[1] & 0x7F
    if length == 126:
        length = struct.unpack(">H", recv_exact(2))[0]
    elif length == 127:
        length = struct.unpack(">Q", recv_exact(8))[0]
    mask_key = recv_exact(4) if masked else b""
    payload = recv_exact(length)
    if masked:
        payload = bytes([payload[i] ^ mask_key[i % 4] for i in range(length)])
    return payload.decode("utf-8", errors="replace")

def rpc(sock, method, params=None, req_id=1):
    req = json.dumps({"jsonrpc": "2.0", "method": method, "params": params or {}, "id": req_id})
    ws_send(sock, req)
    while True:
        raw = ws_recv(sock)
        try:
            resp = json.loads(raw)
            if "id" in resp:
                return resp.get("result", resp.get("error"))
        except Exception:
            pass

def fmt_bytes(b):
    if b is None: return "N/A"
    b = int(b)
    for unit in ["B","KB","MB","GB"]:
        if b < 1024: return f"{b:.1f} {unit}"
        b /= 1024
    return f"{b:.1f} TB"

def main():
    sock = socket.create_connection((HOST, PORT), timeout=10)
    ws_handshake(sock)

    # ── 1. VM 基本信息 ──────────────────────────────────────
    vm = rpc(sock, "getVM", req_id=1)
    print("\n" + "="*60)
    print("📱 Dart VM 信息")
    print("="*60)
    print(f"  版本       : {vm.get('version','?')}")
    print(f"  Dart版本   : {vm.get('dartVersion','?')}")
    print(f"  架构       : {vm.get('architectureBits','?')} bit")
    print(f"  PID        : {vm.get('pid','?')}")
    print(f"  启动时间   : {vm.get('startTime','?')}")

    isolates = vm.get("isolates", [])
    print(f"  Isolate数  : {len(isolates)}")

    # ── 2. 主 Isolate 详情 ─────────────────────────────────
    main_iso = next((i for i in isolates if "main" in i.get("name","").lower()), isolates[0] if isolates else None)
    if main_iso:
        iso_id = main_iso["id"]
        iso = rpc(sock, "getIsolate", {"isolateId": iso_id}, req_id=2)
        print(f"\n{'='*60}")
        print(f"🧵 主 Isolate: {iso.get('name','?')}")
        print(f"{'='*60}")
        print(f"  状态       : {iso.get('runnable','?')}")
        print(f"  暂停事件   : {iso.get('pauseEvent',{}).get('kind','?')}")
        print(f"  线程数     : {len(iso.get('threads',[]))}")
        libs = iso.get("libraries", [])
        print(f"  加载库数   : {len(libs)}")

        # ── 3. 内存快照 ─────────────────────────────────────
        mem = rpc(sock, "getMemoryUsage", {"isolateId": iso_id}, req_id=3)
        if mem:
            print(f"\n{'='*60}")
            print(f"🧠 内存使用")
            print(f"{'='*60}")
            heap_usage = mem.get("heapUsage", {})
            heap_cap   = mem.get("heapCapacity", {})
            ext_usage  = mem.get("externalUsage", 0)
            used   = heap_usage.get("used", 0)
            cap    = heap_usage.get("capacity", 0)
            ext    = int(ext_usage)
            total  = used + ext
            print(f"  堆已用     : {fmt_bytes(used)}")
            print(f"  堆容量     : {fmt_bytes(cap)}")
            print(f"  堆使用率   : {used/cap*100:.1f}%" if cap else "  堆使用率   : N/A")
            print(f"  外部内存   : {fmt_bytes(ext)}")
            print(f"  总计       : {fmt_bytes(total)}")

        # ── 4. CPU 样本 (采集 2 秒) ─────────────────────────
        print(f"\n{'='*60}")
        print(f"⚡ CPU Profiler (采集 2s 样本...)")
        print(f"{'='*60}")
        rpc(sock, "clearCpuSamples", {"isolateId": iso_id}, req_id=4)
        time.sleep(2)
        samples = rpc(sock, "getCpuSamples", {
            "isolateId": iso_id,
            "userTagFilters": [],
        }, req_id=5)
        if samples:
            total_samples = samples.get("sampleCount", 0)
            period_us     = samples.get("samplePeriod", 0)
            max_stack     = samples.get("maxStackDepth", 0)
            print(f"  采样数     : {total_samples}")
            print(f"  采样周期   : {period_us} μs")
            print(f"  最大栈深   : {max_stack}")
            if total_samples and period_us:
                cpu_time_ms = total_samples * period_us / 1000
                wall_ms = 2000
                print(f"  CPU占用估算: {min(cpu_time_ms/wall_ms*100, 100):.1f}%")

            # 分析函数热点 (top frames)
            functions = samples.get("functions", [])
            if functions:
                print(f"\n  🔥 函数热点 Top 15:")
                print(f"  {'独占采样':>8}  {'包含采样':>8}  函数名")
                print(f"  {'-'*8}  {'-'*8}  {'-'*40}")
                sorted_fns = sorted(functions, key=lambda f: f.get("exclusiveTicks",0), reverse=True)
                for fn in sorted_fns[:15]:
                    excl = fn.get("exclusiveTicks", 0)
                    incl = fn.get("inclusiveTicks", 0)
                    name = fn.get("function", {}).get("name", "?")
                    owner = fn.get("function", {}).get("owner", {}).get("name", "")
                    if owner and owner != name:
                        display = f"{owner}.{name}"
                    else:
                        display = name
                    if excl > 0:
                        pct = excl / total_samples * 100 if total_samples else 0
                        print(f"  {excl:>8}  {incl:>8}  {display[:60]} ({pct:.1f}%)")

        # ── 5. VM Flags ──────────────────────────────────────
        flags = rpc(sock, "getFlagList", req_id=6)
        if flags:
            relevant = [f for f in flags.get("flags",[]) if any(k in f.get("name","").lower() for k in ["gc","heap","profile","opt","jit"])]
            if relevant:
                print(f"\n{'='*60}")
                print(f"🏁 相关 VM Flags")
                print(f"{'='*60}")
                for f in relevant[:10]:
                    print(f"  {f['name']:40} = {f.get('valueAsString','?')}")

    # ── 6. 所有 Isolate 内存汇总 ─────────────────────────────
    if len(isolates) > 1:
        print(f"\n{'='*60}")
        print(f"📊 全部 Isolate 内存汇总")
        print(f"{'='*60}")
        total_heap = 0
        for iso_ref in isolates:
            m = rpc(sock, "getMemoryUsage", {"isolateId": iso_ref["id"]}, req_id=99)
            if m:
                used = m.get("heapUsage",{}).get("used", 0)
                total_heap += used
                print(f"  {iso_ref.get('name','?')[:30]:30} heap={fmt_bytes(used)}")
        print(f"  {'合计':30} heap={fmt_bytes(total_heap)}")

    sock.close()
    print(f"\n{'='*60}")
    print("✅ 分析完成")
    print("="*60)

if __name__ == "__main__":
    main()
