#include "flutter_window.h"

#include <optional>
#include <flutter/standard_method_codec.h>
#include <windowsx.h>

#include "flutter/generated_plugin_registrant.h"
#include "window_tasks.h"

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
  const HWND window = GetHandle();
  // 标题栏由 Flutter 绘制，保留系统边框和任务栏菜单。
  SetWindowLongPtr(window, GWL_STYLE, GetWindowLongPtr(window, GWL_STYLE) & ~WS_CAPTION);
  SetWindowPos(window, nullptr, 0, 0, 0, 0,
      SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_FRAMECHANGED);
  const HMENU system_menu = GetSystemMenu(window, FALSE);
  AppendMenu(system_menu, MF_SEPARATOR, 0, nullptr);
  AppendMenu(system_menu, MF_STRING, kExitSystemMenuCommand, L"退出软件");

  window_channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(), "ting_reader/window",
      &flutter::StandardMethodCodec::GetInstance());
  window_channel_->SetMethodCallHandler(
      [this](const auto& call, auto result) {
        const auto& method = call.method_name();
        if (method == "setWindowMode") {
          const auto* value = std::get_if<std::string>(call.arguments());
          if (!value) { result->Error("arguments", "窗口模式参数无效"); return; }
          SetWindowMode(*value);
        } else if (method == "setCloseBehavior") {
          const auto* value = std::get_if<std::string>(call.arguments());
          if (!value) { result->Error("arguments", "关闭行为无效"); return; }
          close_behavior_ = *value;
        } else if (method == "minimize") {
          ShowWindow(GetHandle(), SW_MINIMIZE);
        } else if (method == "close") {
          PostMessage(GetHandle(), WM_CLOSE, 0, 0);
        } else if (method == "startDragging") {
          ReleaseCapture();
          SendMessage(GetHandle(), WM_NCLBUTTONDOWN, HTCAPTION, 0);
        } else if (method == "toggleMaximize") {
          ShowWindow(GetHandle(), IsZoomed(GetHandle()) ? SW_RESTORE : SW_MAXIMIZE);
          result->Success(flutter::EncodableValue(IsZoomed(GetHandle()) != FALSE));
          return;
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
  if (message == kExitApplicationMessage ||
      (message == WM_SYSCOMMAND && (wparam & 0xFFF0) == kExitSystemMenuCommand)) {
    close_behavior_ = "exit";
    PostMessage(hwnd, WM_CLOSE, 0, 0);
    return 0;
  }
  if (message == WM_SIZE && window_channel_ && wparam != SIZE_MINIMIZED) {
    window_channel_->InvokeMethod("maximizedChanged",
        std::make_unique<flutter::EncodableValue>(wparam == SIZE_MAXIMIZED));
  }
  if (message == WM_GETMINMAXINFO && !window_mode_.empty()) {
    auto limits = reinterpret_cast<MINMAXINFO*>(lparam);
    const auto dpi = GetDpiForWindow(hwnd);
    const bool micro = window_mode_ == "micro";
    limits->ptMinTrackSize.x = MulDiv(micro ? 240 : 420, dpi, 96);
    limits->ptMinTrackSize.y = MulDiv(micro ? 50 : 142, dpi, 96);
    return 0;
  }
  if (message == WM_APPCOMMAND && window_channel_) {
    // 系统媒体键与耳机按键会以 WM_APPCOMMAND 到达，转成 Dart 侧的播放指令。
    const WORD command = GET_APPCOMMAND_LPARAM(lparam);
    const char* name = nullptr;
    switch (command) {
      case APPCOMMAND_MEDIA_PLAY_PAUSE:
      case APPCOMMAND_MEDIA_PLAY:
      case APPCOMMAND_MEDIA_PAUSE:
      case APPCOMMAND_MEDIA_STOP:
        name = "playPause";
        break;
      case APPCOMMAND_MEDIA_NEXTTRACK:
        name = "next";
        break;
      case APPCOMMAND_MEDIA_PREVIOUSTRACK:
        name = "previous";
        break;
      case APPCOMMAND_MEDIA_FAST_FORWARD:
        name = "forward";
        break;
      case APPCOMMAND_MEDIA_REWIND:
        name = "rewind";
        break;
      default:
        break;
    }
    if (name != nullptr) {
      window_channel_->InvokeMethod(
          "mediaCommand",
          std::make_unique<flutter::EncodableValue>(std::string(name)));
      return 0;
    }
  }
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

void FlutterWindow::SetWindowMode(const std::string& mode) {
  if (mode == window_mode_) return;
  const HWND window = GetHandle();
  const bool leaving_compact = mode == "normal";
  if (window_mode_.empty() && !leaving_compact) {
    // 从普通窗口进入紧凑窗口前，记住原来的位置与尺寸。
    GetWindowPlacement(window, &normal_placement_);
    ShowWindow(window, SW_RESTORE);
  }
  RECT bounds;
  GetWindowRect(window, &bounds);
  const auto dpi = GetDpiForWindow(window);
  if (leaving_compact) {
    SetWindowPos(window, HWND_NOTOPMOST, 0, 0, 0, 0,
                 SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
    SetWindowPlacement(window, &normal_placement_);
  } else {
    const bool micro = mode == "micro";
    SetWindowPos(window, HWND_TOPMOST, bounds.left, bounds.top,
                 MulDiv(micro ? 300 : 560, dpi, 96),
                 MulDiv(micro ? 66 : 156, dpi, 96), SWP_SHOWWINDOW);
  }
  window_mode_ = leaving_compact ? std::string() : mode;
}
