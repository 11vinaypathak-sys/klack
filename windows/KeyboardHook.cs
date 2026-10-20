using System.Diagnostics;
using System.Runtime.InteropServices;

namespace Klack;

/// <summary>
/// Global low-level keyboard hook (WH_KEYBOARD_LL). Listen-only: every event is
/// passed straight on with CallNextHookEx, nothing is swallowed, nothing is
/// logged or stored. The callback only reports "a key went down / up" and
/// whether it was the space bar.
/// </summary>
public sealed class KeyboardHook : IDisposable
{
    public event Action<bool /*isSpace*/>? KeyDown;
    public event Action<bool /*isSpace*/>? KeyUp;

    private const int WH_KEYBOARD_LL = 13;
    private const int WM_KEYDOWN = 0x0100;
    private const int WM_KEYUP = 0x0101;
    private const int WM_SYSKEYDOWN = 0x0104;
    private const int WM_SYSKEYUP = 0x0105;
    private const int VK_SPACE = 0x20;

    // KBDLLHOOKSTRUCT.flags
    private const uint LLKHF_INJECTED = 0x10;

    [StructLayout(LayoutKind.Sequential)]
    private struct KBDLLHOOKSTRUCT
    {
        public uint vkCode;
        public uint scanCode;
        public uint flags;
        public uint time;
        public IntPtr dwExtraInfo;
    }

    private delegate IntPtr LowLevelKeyboardProc(int nCode, IntPtr wParam, IntPtr lParam);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern IntPtr SetWindowsHookEx(int idHook, LowLevelKeyboardProc lpfn, IntPtr hMod, uint dwThreadId);

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool UnhookWindowsHookEx(IntPtr hhk);

    [DllImport("user32.dll")]
    private static extern IntPtr CallNextHookEx(IntPtr hhk, int nCode, IntPtr wParam, IntPtr lParam);

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern IntPtr GetModuleHandle(string? lpModuleName);

    // Kept as a field so the GC never collects the delegate the OS is calling.
    private readonly LowLevelKeyboardProc _proc;
    private IntPtr _hook = IntPtr.Zero;

    // Auto-repeat filter. WH_KEYBOARD_LL does not set bit 30 ("previous key
    // state") the way WM_KEYDOWN does, so repeats are detected by remembering
    // which virtual keys are currently held and ignoring a second down for
    // the same key until its up arrives.
    private readonly bool[] _held = new bool[256];

    public KeyboardHook()
    {
        _proc = HookCallback;
    }

    /// <summary>Must be called on a thread that pumps messages (the UI thread).</summary>
    public void Install()
    {
        if (_hook != IntPtr.Zero) return;
        using var module = Process.GetCurrentProcess().MainModule;
        _hook = SetWindowsHookEx(WH_KEYBOARD_LL, _proc, GetModuleHandle(module?.ModuleName), 0);
        if (_hook == IntPtr.Zero)
            throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error(), "SetWindowsHookEx failed");
    }

    public void Uninstall()
    {
        if (_hook == IntPtr.Zero) return;
        UnhookWindowsHookEx(_hook);
        _hook = IntPtr.Zero;
        Array.Clear(_held);
    }

    private IntPtr HookCallback(int nCode, IntPtr wParam, IntPtr lParam)
    {
        if (nCode >= 0)
        {
            try
            {
                var data = Marshal.PtrToStructure<KBDLLHOOKSTRUCT>(lParam);
                int vk = (int)(data.vkCode & 0xFF);
                bool isSpace = vk == VK_SPACE;
                bool injected = (data.flags & LLKHF_INJECTED) != 0;
                int msg = (int)wParam;

                if (!injected)
                {
                    if (msg == WM_KEYDOWN || msg == WM_SYSKEYDOWN)
                    {
                        if (!_held[vk])
                        {
                            _held[vk] = true;
                            KeyDown?.Invoke(isSpace);
                        }
                        // else: auto-repeat while held -> ignored
                    }
                    else if (msg == WM_KEYUP || msg == WM_SYSKEYUP)
                    {
                        _held[vk] = false;
                        KeyUp?.Invoke(isSpace);
                    }
                }
            }
            catch
            {
                // Never let an exception escape into the hook chain.
            }
        }
        // Always pass the event on. The hook never blocks or alters keys.
        return CallNextHookEx(_hook, nCode, wParam, lParam);
    }

    public void Dispose() => Uninstall();
}
