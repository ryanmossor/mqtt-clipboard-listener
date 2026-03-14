using System.Text.Json.Serialization;

namespace Mqtt.Clipboard;

[method: JsonConstructor]
public class MqttClipboardPayload(string text)
{
    public string Text { get; init; } = text;
}
