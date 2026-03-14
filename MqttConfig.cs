namespace Mqtt.Clipboard;

public class MqttConfig
{
    public string Endpoint { get; set; } = "localhost";
    public int Port { get; set; } = 1883;
    public string Username { get; set; } = "";
    public string Password { get; set; } = "";
    public string Topic { get; set; } = "clipboard";
}
