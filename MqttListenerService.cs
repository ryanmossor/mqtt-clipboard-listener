using System.Diagnostics;
using System.Text.Json;
using MQTTnet;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Options;
using TextCopy;

namespace Mqtt.Clipboard;

public class MqttListenerService : BackgroundService
{
    private readonly IMqttClient _client;
    private readonly MqttClientOptions _mqttOptions;
    private readonly MqttConfig _mqttConfig;
    private readonly JsonSerializerOptions _jsonOptions;

    private const string NotificationTitle = "📋 Clipboard Set";

    public MqttListenerService(IOptions<MqttConfig> mqttConfig)
    {
        _mqttConfig = mqttConfig.Value;

        var factory = new MqttClientFactory();
        _client = factory.CreateMqttClient();
        _client.ApplicationMessageReceivedAsync += HandleMessage;

        _mqttOptions = new MqttClientOptionsBuilder()
            .WithTcpServer(_mqttConfig.Endpoint, _mqttConfig.Port)
            .WithCredentials(_mqttConfig.Username, _mqttConfig.Password)
            .WithCleanSession()
            .WithClientId(Environment.MachineName)
            .Build();

        _jsonOptions = new JsonSerializerOptions
        {
            PropertyNameCaseInsensitive = true,
            WriteIndented = true
        };
    }

    protected override async Task ExecuteAsync(CancellationToken cancellationToken)
    {
        Console.WriteLine("Starting shared clipboard service...");

        while (!cancellationToken.IsCancellationRequested)
        {
            try
            {
                if (!_client.IsConnected)
                {
                    Console.WriteLine($"Connecting to MQTT broker {_mqttConfig.Endpoint}:{_mqttConfig.Port}...");
                    await _client.ConnectAsync(_mqttOptions, cancellationToken);
                    await _client.SubscribeAsync(_mqttConfig.Topic, cancellationToken: cancellationToken);
                    Console.WriteLine($"Subscribed to topic '{_mqttConfig.Topic}'");
                }
            }
            catch (OperationCanceledException) { } // do nothing
            catch (Exception ex)
            {
                Console.WriteLine($"Connection failed: {ex.Message}");
            }

            try
            {
                await Task.Delay(TimeSpan.FromSeconds(5), cancellationToken);
            }
            catch (TaskCanceledException)
            {
                break;
            }
        }
    }

    public override async Task StopAsync(CancellationToken cancellationToken)
    {
        Console.WriteLine("Stopping shared clipboard service...");
        if (_client.IsConnected)
        {
            await _client.DisconnectAsync();
        }
        await base.StopAsync(cancellationToken);
    }

    private async Task HandleMessage(MqttApplicationMessageReceivedEventArgs args)
    {
        try
        {
            string payloadAsString = args.ApplicationMessage.ConvertPayloadToString();
            var payload = JsonSerializer.Deserialize<MqttClipboardPayload>(payloadAsString, _jsonOptions);
            if (payload == null)
            {
                Console.WriteLine($"Invalid message payload: {payloadAsString}");
                return;
            }

            Console.WriteLine($"[topic:{_mqttConfig.Topic}] Copying {payload.Text} to clipboard");
            await ClipboardService.SetTextAsync(payload.Text);

            SendNotification(payload.Text);
        }
        catch (Exception ex)
        {
            Console.WriteLine($"Error handling message: {ex}");
        }
    }

    private void SendNotification(string body)
    {
        if (OperatingSystem.IsLinux())
        {
            Process.Start("notify-send", [
                "--urgency", "normal",
                "--expire-time", "5000",
                NotificationTitle,
                body
            ]);
        }
        else if (OperatingSystem.IsMacOS())
        {
            Process.Start("osascript", ["-e", $"display notification \"{body}\" with title \"{NotificationTitle}\""]);
        }
    }
}
