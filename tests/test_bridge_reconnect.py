"""The bridge must notice a dropped Home Assistant socket and reconnect with a fresh snapshot."""
import asyncio, json, os, subprocess, sys, tempfile, pathlib
from aiohttp import web

BRIDGE = str(pathlib.Path(__file__).parents[1] / "bin" / "dabber-bridge")

async def handler(request):
    ws = web.WebSocketResponse(); await ws.prepare(request)
    request.app["conns"] += 1; n = request.app["conns"]
    await ws.send_json({"type": "auth_required"}); await ws.receive_json(); await ws.send_json({"type": "auth_ok"})
    async for m in ws:
        c = json.loads(m.data)
        if c["type"] == "config/entity_registry/list":
            await ws.send_json({"id": c["id"], "type": "result", "success": True, "result": [
                {"entity_id": "select.x_led_mode", "platform": "dr_dabber", "unique_id": "AA:BB_led_mode"}]})
        elif c["type"] == "subscribe_trigger":
            await ws.send_json({"id": c["id"], "type": "result", "success": True, "result": None})
        elif c["type"] == "get_states":
            opts = ["1", "2"] if n == 1 else ["Stealth", "Calm"]          # options change between connections
            await ws.send_json({"id": c["id"], "type": "result", "success": True, "result": [
                {"entity_id": "select.x_led_mode", "state": opts[0], "attributes": {"options": opts}}]})
            if n == 1:
                await asyncio.sleep(0.3); await ws.close()                  # simulate HA restart
    return ws

def test_reconnects_after_socket_drop():
    async def go():
        app = web.Application(); app["conns"] = 0; app.router.add_get("/api/websocket", handler)
        runner = web.AppRunner(app); await runner.setup(); site = web.TCPSite(runner, "127.0.0.1", 0); await site.start()
        port = site._server.sockets[0].getsockname()[1]
        tok = tempfile.NamedTemporaryFile("w", delete=False); tok.write("tok"); tok.close()
        p = await asyncio.create_subprocess_exec(sys.executable, BRIDGE, "--url", f"http://127.0.0.1:{port}", "--token-file", tok.name,
                                                 stdin=asyncio.subprocess.PIPE, stdout=asyncio.subprocess.PIPE)
        snaps, conns = [], []
        try:
            async def read():
                while len(snaps) < 2:
                    line = await p.stdout.readline()
                    if not line: break
                    m = json.loads(line)
                    if m["t"] == "snapshot": snaps.append(m["entities"]["led_mode"]["attrs"]["options"])
                    if m["t"] == "conn": conns.append(m["ok"])
            await asyncio.wait_for(read(), 20)
        finally:
            p.kill(); await runner.cleanup(); os.unlink(tok.name)
        assert snaps == [["1", "2"], ["Stealth", "Calm"]], snaps       # fresh options after reconnect
        assert False in conns, conns                                    # and the drop was reported
    asyncio.run(go())
