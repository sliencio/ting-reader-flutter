#include "flutter_window.h"

#include <optional>
#include <flutter/standard_method_codec.h>

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

  window_channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(), "ting_reader/window",
      &flutter::StandardMethodCodec::GetInstance());
  window_channel_->SetMethodCallHandler(
      [this](const auto& call, auto result) {
        const auto& method = call.method_name();
        if (method == "setMiniMode") {
          const auto* value = std::get_if<bool>(call.arguments());
          if (!value) { result->Error("arguments", "小窗参数无效"); return; }
          SetMiniMode(*value);
        } else if (method == "setCloseBehavior") {
          const auto* value = std::get_if<std::string>(call.arguments());
          if (!value) { result->Error("arguments", "关闭行为无效"); return; }
          close_behavior_ = *value;
        } else if (method == "minimize") {
          ShowWindow(GetHandle(), SW_MINIMIZE);
        } else if (method == "exit") {
          close_behavior_ = "exit";
          PostMessage(GetHandle(), WM_CLOSE, 0, 0);
        } else {
          result->NotImplemented();
          return;
        }
        result->Success();
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
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  if (message == WM_CLOSE) {
    if (close_behavior_ == "minimize") {
      ShowWindow(hwnd, SW_MINIMIZE);
      return 0;
    }
    if (close_behavior_ != "exit" && window_channel_) {
      window_channel_->InvokeMethod("closeRequested", nullptr);
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

void FlutterWindow::SetMiniMode(bool enabled) {
  if (mini_mode_ == enabled) return;
  const HWND window = GetHandle();
  if (enabled) {
    GetWindowPlacement(window, &normal_placement_);
    ShowWindow(window, SW_RESTORE);
    RECT bounds;
    GetWindowRect(window, &bounds);
    const auto dpi = GetDpiForWindow(window);
    SetWindowPos(window, HWND_TOPMOST, bounds.left, bounds.top,
                 MulDiv(400, dpi, 96), MulDiv(260, dpi, 96), SWP_SHOWWINDOW);
  } else {
    SetWindowPos(window, HWND_NOTOPMOST, 0, 0, 0, 0,
                 SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
    SetWindowPlacement(window, &normal_placement_);
  }
  mini_mode_ = enabled;
}
