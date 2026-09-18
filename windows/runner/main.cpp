#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  bool start_hidden = false;
  for (const auto& arg : command_line_arguments) {
    if (arg == "--autostart" || arg == "--hidden" || arg == "-hidden") {
      start_hidden = true;
      break;
    }
  }

  // Single Instance Mutex & Window Wakeup
  const wchar_t kPCLinkMutexName[] = L"Local\\PCLink_Application_Instance_Mutex_v1";
  const UINT kPCLinkShowWindowMessage = ::RegisterWindowMessage(L"PCLink_ShowWindow_Broadcast_Message");

  HANDLE hMutex = ::CreateMutex(nullptr, FALSE, kPCLinkMutexName);
  if (hMutex != nullptr && ::GetLastError() == ERROR_ALREADY_EXISTS) {
    // Another instance of PCLink is already active in background or foreground.
    // Signal the running instance to wake up, restore, and display its UI.
    HWND existing_window = ::FindWindow(L"FLUTTER_RUNNER_WIN32_WINDOW", L"pclink");
    if (existing_window != nullptr) {
      ::PostMessage(existing_window, kPCLinkShowWindowMessage, 0, 0);
      ::ShowWindow(existing_window, SW_SHOW);
      ::ShowWindow(existing_window, SW_RESTORE);
      ::SetForegroundWindow(existing_window);
    } else {
      ::PostMessage(HWND_BROADCAST, kPCLinkShowWindowMessage, 0, 0);
    }
    ::CloseHandle(hMutex);
    ::CoUninitialize();
    return EXIT_SUCCESS;
  }

  flutter::DartProject project(L"data");
  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  window.SetStartHidden(start_hidden);

  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"pclink", origin, size)) {
    if (hMutex) {
      ::ReleaseMutex(hMutex);
      ::CloseHandle(hMutex);
    }
    ::CoUninitialize();
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  if (hMutex) {
    ::ReleaseMutex(hMutex);
    ::CloseHandle(hMutex);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
