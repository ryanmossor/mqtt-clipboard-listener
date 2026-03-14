using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Configuration;
using Mqtt.Clipboard;

try
{
    var builder = Host.CreateDefaultBuilder(args);

    builder.ConfigureAppConfiguration((context, config) =>
    {
        config.AddJsonFile("appsettings.json", optional: true);
    });

    builder.ConfigureServices((context, services) =>
    {
        services.Configure<MqttConfig>(context.Configuration.GetSection("Mqtt"));
        services.AddHostedService<MqttListenerService>();
    });

    builder.UseConsoleLifetime();

    var app = builder.Build();
    app.Run();
}
catch (Exception ex)
{
    Console.WriteLine(ex);
}
