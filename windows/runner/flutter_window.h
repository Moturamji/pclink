#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <windows.h>
#include <shellapi.h>

#include <memory>

#include "win32_window.h"

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

  void SetStartHidden(bool hidden) { start_hidden_ = hidden; }
  bool IsStartHidden() const { return start_hidden_; }

  void ShowWindowAndBringToFront();
  void HideWindowToTray();
  void SetupTrayIcon();
  void RemoveTrayIcon();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  bool start_hidden_ = false;
  NOTIFYICONDATA nid_{};
  bool tray_icon_created_ = false;

  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> window_channel_;
  std::vector<std::string> pending_shared_files_;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
