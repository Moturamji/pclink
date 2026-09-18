#include "flutter_window.h"

#include <optional>
#include <shellapi.h>

#include "flutter/generated_plugin_registrant.h"
#include "native_screen_share.h"
#include "resource.h"

static const UINT g_show_window_message =
    ::RegisterWindowMessage(L"PCLink_ShowWindow_Broadcast_Message");

#define WM_PCLINK_TRAY_CALLBACK (WM_USER + 101)
#define IDM_TRAY_SHOW (WM_USER + 102)
#define IDM_TRAY_HIDE (WM_USER + 103)
#define IDM_TRAY_EXIT (WM_USER + 104)

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  pclink::NativeScreenShare::RegisterWithMessenger(flutter_controller_->engine()->messenger());

  // Register window control method channel for Flutter/Dart
  window_channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(),
      "pclink/window_control",
      &flutter::StandardMethodCodec::GetInstance());

  window_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        if (call.method_name() == "isStartedHidden") {
          result->Success(flutter::EncodableValue(this->IsStartHidden()));
        } else if (call.method_name() == "showWindow") {
          this->ShowWindowAndBringToFront();
          result->Success();
        } else if (call.method_name() == "hideWindow") {
          this->HideWindowToTray();
          result->Success();
        } else {
          result->NotImplemented();
        }
      });

  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  // Setup Windows system tray icon in notification area
  SetupTrayIcon();

  // If started normally (not --autostart or --hidden), show the window on the first frame.
  if (!start_hidden_) {
    flutter_controller_->engine()->SetNextFrameCallback([&]() {
      this->Show();
    });
  }

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  RemoveTrayIcon();

  if (window_channel_) {
    window_channel_ = nullptr;
  }

  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

void FlutterWindow::SetupTrayIcon() {
  HWND hwnd = GetHandle();
  if (!hwnd) return;

  memset(&nid_, 0, sizeof(NOTIFYICONDATA));
  nid_.cbSize = sizeof(NOTIFYICONDATA);
  nid_.hWnd = hwnd;
  nid_.uID = 1;
  nid_.uFlags = NIF_ICON | NIF_MESSAGE | NIF_TIP;
  nid_.uCallbackMessage = WM_PCLINK_TRAY_CALLBACK;

  nid_.hIcon = (HICON)GetClassLongPtr(hwnd, GCLP_HICON);
  if (!nid_.hIcon) {
    nid_.hIcon = LoadIcon(GetModuleHandle(nullptr), MAKEINTRESOURCE(IDI_APP_ICON));
  }
  wcscpy_s(nid_.szTip, L"PCLink - Live Sync & Server");

  Shell_NotifyIcon(NIM_ADD, &nid_);
  tray_icon_created_ = true;
}

void FlutterWindow::RemoveTrayIcon() {
  if (tray_icon_created_) {
    Shell_NotifyIcon(NIM_DELETE, &nid_);
    tray_icon_created_ = false;
  }
}

void FlutterWindow::ShowWindowAndBringToFront() {
  HWND hwnd = GetHandle();
  if (hwnd) {
    ::ShowWindow(hwnd, SW_SHOW);
    ::ShowWindow(hwnd, SW_RESTORE);
    ::SetForegroundWindow(hwnd);
  }
}

void FlutterWindow::HideWindowToTray() {
  HWND hwnd = GetHandle();
  if (hwnd) {
    ::ShowWindow(hwnd, SW_HIDE);
  }
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // 1. Handle broadcast wake-up message from a secondary instance launch
  if (message == g_show_window_message) {
    ShowWindowAndBringToFront();
    return 0;
  }

  // 2. Handle System Tray interactions
  if (message == WM_PCLINK_TRAY_CALLBACK) {
    if (lparam == WM_LBUTTONUP || lparam == WM_LBUTTONDBLCLK) {
      ShowWindowAndBringToFront();
      return 0;
    } else if (lparam == WM_RBUTTONUP) {
      POINT pt;
      GetCursorPos(&pt);
      HMENU hMenu = CreatePopupMenu();
      AppendMenu(hMenu, MF_STRING, IDM_TRAY_SHOW, L"Open PCLink");
      AppendMenu(hMenu, MF_STRING, IDM_TRAY_HIDE, L"Hide to Tray");
      AppendMenu(hMenu, MF_SEPARATOR, 0, nullptr);
      AppendMenu(hMenu, MF_STRING, IDM_TRAY_EXIT, L"Exit PCLink");

      SetForegroundWindow(hwnd);
      int cmd = TrackPopupMenu(hMenu, TPM_RETURNCMD | TPM_NONOTIFY, pt.x, pt.y, 0, hwnd, nullptr);
      DestroyMenu(hMenu);

      if (cmd == IDM_TRAY_SHOW) {
        ShowWindowAndBringToFront();
      } else if (cmd == IDM_TRAY_HIDE) {
        HideWindowToTray();
      } else if (cmd == IDM_TRAY_EXIT) {
        Destroy();
      }
      return 0;
    }
  }

  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
