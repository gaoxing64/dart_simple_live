#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // 单实例检测用命名互斥量而非窗口标题：上游 Slive 版窗口标题同为 "Slive"，
  // 按标题 FindWindow 会把上游窗口误判为本应用实例导致拒绝启动。
  // 互斥量名带构建标识，与上游版互不干扰；检测到已有实例时尝试将其前置。
  HANDLE single_instance = ::CreateMutexW(nullptr, TRUE, L"Local\\Slive-gaoxing-SingleInstance");
  if (single_instance == nullptr) {
    return EXIT_FAILURE;
  }
  if (::GetLastError() == ERROR_ALREADY_EXISTS) {
    HWND hwnd = ::FindWindow(L"FLUTTER_RUNNER_GAOXING_WINDOW", nullptr);
    if (hwnd != NULL) {
      ::ShowWindow(hwnd, SW_NORMAL);
      ::SetForegroundWindow(hwnd);
    }
    ::CloseHandle(single_instance);
    return EXIT_FAILURE;
  }

  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  // crash on debug, release is ok, disabled impeller temp
  project.set_impeller_switch(flutter::ImpellerSwitch::Disabled);

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"Slive", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  ::CloseHandle(single_instance);
  return EXIT_SUCCESS;
}
