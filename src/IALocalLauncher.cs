using System;
using System.Diagnostics;
using System.IO;
using System.Windows.Forms;

[assembly: System.Reflection.AssemblyTitle("IA Local")]
[assembly: System.Reflection.AssemblyDescription("Lanzador del chat local con Ollama")]
[assembly: System.Reflection.AssemblyCompany("IA Local")]
[assembly: System.Reflection.AssemblyProduct("IA Local")]
[assembly: System.Reflection.AssemblyVersion("1.0.0.0")]

internal static class Program
{
    [STAThread]
    private static void Main()
    {
        string folder = AppDomain.CurrentDomain.BaseDirectory;
        string launcher = Path.Combine(folder, "iniciar-chat.vbs");

        if (!File.Exists(launcher))
        {
            MessageBox.Show(
                "No se encontró iniciar-chat.vbs junto al ejecutable.",
                "IA Local",
                MessageBoxButtons.OK,
                MessageBoxIcon.Error
            );
            return;
        }

        try
        {
            Process.Start(new ProcessStartInfo
            {
                FileName = "wscript.exe",
                Arguments = "\"" + launcher + "\"",
                WorkingDirectory = folder,
                UseShellExecute = false,
                CreateNoWindow = true,
                WindowStyle = ProcessWindowStyle.Hidden
            });
        }
        catch (Exception error)
        {
            MessageBox.Show(
                "No se pudo iniciar IA Local.\n\n" + error.Message,
                "IA Local",
                MessageBoxButtons.OK,
                MessageBoxIcon.Error
            );
        }
    }
}
