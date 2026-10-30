// 上游：flutter/windows/runner/win32_desktop.h@bd9262397（复制后修改）
#ifndef RUNNER_WIN32_DESKTOP_H_
#define RUNNER_WIN32_DESKTOP_H_

#include "win32_window.h"

namespace Win32Desktop
{
  void GetWorkArea(Win32Window::Point& origin, Win32Window::Size& size);
  void FitToWorkArea(Win32Window::Point& origin, Win32Window::Size& size);
  // leapgate: main window sizing, see win32_desktop.cpp.
  void GetMonitorWorkArea(HMONITOR monitor, RECT& work, double& scale);
  SIZE MinClientSize(const RECT& work, double scale, SIZE frame, const Win32Window::Size& min_size);
  SIZE DefaultClientSize(const RECT& work, double scale, SIZE frame,
                         const Win32Window::Size& default_size, const Win32Window::Size& min_size);
  void GetMainWindowBounds(const Win32Window::Size& default_size, const Win32Window::Size& min_size,
                           Win32Window::Point& origin, Win32Window::Size& size);
  bool BumpMouse(int dx, int dy);
}

#endif  // RUNNER_WIN32_DESKTOP_H_
