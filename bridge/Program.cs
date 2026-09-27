using System.Net;
using System.Net.WebSockets;
using System.Text;
using System.Text.Json;

const int tswPort = 31270;
const int wsPort = 31271;
const string wsPath = "/ebula";

var keyPath = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments),
    "My Games", "TrainSimWorld6", "Saved", "Config", "CommAPIKey.txt");
string? apiKey = File.Exists(keyPath) ? (await File.ReadAllTextAsync(keyPath)).Trim() : null;

using var http = new HttpClient { BaseAddress = new Uri("http://127.0.0.1:" + tswPort) };
if (!string.IsNullOrWhiteSpace(apiKey))
    http.DefaultRequestHeaders.TryAddWithoutValidation("DTGCommKey", apiKey);

var listener = new HttpListener();
listener.Prefixes.Add("http://0.0.0.0:" + wsPort + "/");
listener.Start();

var clients = new List<WebSocket>();
Console.WriteLine("TSW6 EBuLa Bridge");
Console.WriteLine("TSW HTTP API: http://127.0.0.1:" + tswPort);
Console.WriteLine("WebSocket: ws://0.0.0.0:" + wsPort + wsPath);
Console.WriteLine("CommAPIKey: " + (apiKey == null ? "NOT FOUND" : "loaded"));

_ = Task.Run(async () => {
    while (true) {
        var ctx = await listener.GetContextAsync();
        if (!ctx.Request.IsWebSocketRequest || ctx.Request.Url?.AbsolutePath != wsPath) {
            ctx.Response.StatusCode = 404;
            ctx.Response.Close();
            continue;
        }
        var ws = (await ctx.AcceptWebSocketAsync(null)).WebSocket;
        lock (clients) clients.Add(ws);
        _ = Task.Run(async () => {
            var buffer = new byte[256];
            try { while (ws.State == WebSocketState.Open) await ws.ReceiveAsync(buffer, CancellationToken.None); }
            catch { }
            finally { lock (clients) clients.Remove(ws); ws.Dispose(); }
        });
    }
});

while (true) {
    var telemetry = await ReadTelemetryAsync(http);
    var payload = JsonSerializer.Serialize(new { type = "telemetry", data = telemetry });
    var bytes = Encoding.UTF8.GetBytes(payload);

    List<WebSocket> snapshot;
    lock (clients) snapshot = clients.ToList();
    foreach (var ws in snapshot) {
        if (ws.State != WebSocketState.Open) continue;
        try { await ws.SendAsync(bytes, WebSocketMessageType.Text, true, CancellationToken.None); }
        catch { }
    }
    await Task.Delay(250);
}

static async Task<object> ReadTelemetryAsync(HttpClient http) {
    try {
        var speed = await GetDoubleAsync(http, "/get/CurrentDrivableActor.Function.HUD_GetSpeed");
        return new {
            connected = true,
            speedKmh = speed ?? 0,
            simulationTime = (string?)null
        };
    } catch {
        return new {
            connected = false,
            speedKmh = 0,
            simulationTime = (string?)null
        };
    }
}

static async Task<double?> GetDoubleAsync(HttpClient http, string path) {
    using var r = await http.GetAsync(path);
    if (!r.IsSuccessStatusCode) return null;
    var text = await r.Content.ReadAsStringAsync();
    if (double.TryParse(text.Trim(), out var d)) return d;
    try {
        using var doc = JsonDocument.Parse(text);
        var root = doc.RootElement;
        if (root.ValueKind == JsonValueKind.Number) return root.GetDouble();
        foreach (var name in new[] { "Value", "value", "Result", "result" })
            if (root.TryGetProperty(name, out var p) && p.ValueKind == JsonValueKind.Number)
                return p.GetDouble();
    } catch { }
    return null;
}
