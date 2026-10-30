// TclAutoRes.exe - tray launcher. Build it with tools\Build-Exe.ps1 (no administrator rights, no download).
//
// Runs TclAutoResTray.ps1 inside this process with the Windows PowerShell 5.1 engine, so Windows lists the
// tray icon as "TclAutoRes" (taskbar settings, Task Manager) instead of "Windows PowerShell".
// It is a GUI program: no console window. It does nothing else; all logic stays in the .ps1/.psm1 files.
//
// Usage: TclAutoRes.exe [-Config <path to config.json>]
// C# 5 only (the compiler that ships with .NET Framework 4).

using System;
using System.IO;
using System.Management.Automation;
using System.Management.Automation.Runspaces;
using System.Reflection;
using System.Windows.Forms;

[assembly: AssemblyTitle("TclAutoRes")]
[assembly: AssemblyProduct("TclAutoRes")]
[assembly: AssemblyDescription("TclAutoRes tray launcher (runs TclAutoResTray.ps1)")]
[assembly: AssemblyCopyright("MIT License")]
[assembly: AssemblyVersion("2.0.1.0")]
[assembly: AssemblyFileVersion("2.0.1.0")]

static class TclAutoResLauncher
{
    [STAThread]
    static int Main(string[] args)
    {
        string root = AppDomain.CurrentDomain.BaseDirectory;
        string script = Path.Combine(root, "TclAutoResTray.ps1");
        string config = "";
        for (int i = 0; i < args.Length; i++)
        {
            if (string.Equals(args[i], "-Config", StringComparison.OrdinalIgnoreCase) && i + 1 < args.Length) { config = args[++i]; }
            else { Fail("Unknown argument: " + args[i] + "\r\n\r\nUsage: TclAutoRes.exe [-Config <path>]"); return 2; }
        }
        if (!File.Exists(script)) { Fail("Not found: " + script + "\r\n\r\nKeep TclAutoRes.exe in the TclAutoRes folder."); return 1; }

        try
        {
            InitialSessionState iss = InitialSessionState.CreateDefault();
            // Same as "powershell -ExecutionPolicy Bypass": applies to this process only.
            iss.ExecutionPolicy = Microsoft.PowerShell.ExecutionPolicy.Bypass;
            using (Runspace runspace = RunspaceFactory.CreateRunspace(iss))
            {
                // Run on this STA thread: the tray uses Windows Forms.
                runspace.ThreadOptions = PSThreadOptions.UseCurrentThread;
                runspace.Open();
                using (PowerShell ps = PowerShell.Create())
                {
                    ps.Runspace = runspace;
                    ps.AddCommand(script);
                    if (config.Length > 0) { ps.AddParameter("Config", config); }
                    ps.Invoke();
                }
            }
        }
        catch (Exception ex)
        {
            Fail(ex.Message);
            return 1;
        }
        return 0;
    }

    static void Fail(string message)
    {
        MessageBox.Show("TclAutoRes: " + message, "TclAutoRes", MessageBoxButtons.OK, MessageBoxIcon.Error);
    }
}
