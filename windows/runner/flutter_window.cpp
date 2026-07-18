#include "flutter_window.h"

#include <algorithm>
#include <flutter/standard_method_codec.h>
#include <flutter_windows.h>
#include <optional>

#include "flutter/generated_plugin_registrant.h"

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
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  window_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "com.zanzibarr/window",
          &flutter::StandardMethodCodec::GetInstance());
  window_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<
                 flutter::MethodResult<flutter::EncodableValue>> result) {
        bool changed = false;
        if (call.method_name() == "enterPictureInPicture") {
          changed = EnterPictureInPicture();
        } else if (call.method_name() == "exitPictureInPicture") {
          changed = ExitPictureInPicture();
        } else {
          result->NotImplemented();
          return;
        }
        result->Success(flutter::EncodableValue(changed));
      });

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  window_channel_.reset();
  is_picture_in_picture_ = false;
  picture_in_picture_restore_placement_ = {};

  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

bool FlutterWindow::EnterPictureInPicture() {
  HWND window = GetHandle();
  if (!window || !IsWindow(window)) {
    return false;
  }
  if (is_picture_in_picture_) {
    return true;
  }

  WINDOWPLACEMENT placement{};
  placement.length = sizeof(WINDOWPLACEMENT);
  if (!GetWindowPlacement(window, &placement)) {
    return false;
  }

  HMONITOR monitor = MonitorFromWindow(window, MONITOR_DEFAULTTONEAREST);
  MONITORINFO monitor_info{};
  monitor_info.cbSize = sizeof(MONITORINFO);
  if (!monitor || !GetMonitorInfo(monitor, &monitor_info)) {
    return false;
  }

  UINT dpi = FlutterDesktopGetDpiForHWND(window);
  if (dpi == 0) {
    dpi = 96;
  }

  const int margin = std::max(0, MulDiv(24, dpi, 96));
  int width = std::max(1, MulDiv(480, dpi, 96));
  int height = std::max(1, MulDiv(270, dpi, 96));
  const RECT& work = monitor_info.rcWork;
  const int available_width =
      std::max(1, static_cast<int>(work.right - work.left) - 2 * margin);
  const int available_height =
      std::max(1, static_cast<int>(work.bottom - work.top) - 2 * margin);

  // Preserve the approximate 16:9 shape even on unusually small work areas.
  const double fit =
      std::min({1.0, static_cast<double>(available_width) / width,
                static_cast<double>(available_height) / height});
  width = std::max(1, static_cast<int>(width * fit));
  height = std::max(1, static_cast<int>(height * fit));

  const int x = std::max(static_cast<int>(work.left),
                         static_cast<int>(work.right) - width - margin);
  const int y = std::max(static_cast<int>(work.top),
                         static_cast<int>(work.bottom) - height - margin);

  // SetWindowPos does not reliably resize a maximized/minimized HWND until it
  // has been restored. The original show state remains in WINDOWPLACEMENT and
  // is reinstated verbatim on exit.
  if (IsZoomed(window) || IsIconic(window)) {
    ShowWindow(window, SW_RESTORE);
  }

  if (!SetWindowPos(window, HWND_TOPMOST, x, y, width, height,
                    SWP_NOACTIVATE | SWP_SHOWWINDOW)) {
    SetWindowPlacement(window, &placement);
    SetWindowPos(window, HWND_NOTOPMOST, 0, 0, 0, 0,
                 SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
    return false;
  }

  picture_in_picture_restore_placement_ = placement;
  is_picture_in_picture_ = true;
  return true;
}

bool FlutterWindow::ExitPictureInPicture() {
  HWND window = GetHandle();
  if (!window || !IsWindow(window)) {
    return false;
  }

  // Repeated exits remain successful and also guarantee that the normal
  // window cannot accidentally stay topmost after a delayed duplicate call.
  if (!is_picture_in_picture_) {
    return SetWindowPos(window, HWND_NOTOPMOST, 0, 0, 0, 0,
                        SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE) != FALSE;
  }

  const bool placement_restored =
      SetWindowPlacement(window, &picture_in_picture_restore_placement_) !=
      FALSE;
  const bool topmost_removed =
      SetWindowPos(window, HWND_NOTOPMOST, 0, 0, 0, 0,
                   SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE) != FALSE;
  if (placement_restored && topmost_removed) {
    is_picture_in_picture_ = false;
    picture_in_picture_restore_placement_ = {};
    return true;
  }
  return false;
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
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
