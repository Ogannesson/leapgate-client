// 上游：flutter/windows/runner/win32_desktop.cpp@bd9262397（复制后修改）
#include "win32_desktop.h"

#include <flutter_windows.h>
#include <windows.h>

#include <algorithm>

namespace Win32Desktop
{
  void GetWorkArea(Win32Window::Point& origin, Win32Window::Size& size)
  {
    RECT windowRect;

    windowRect.left = origin.x;
    windowRect.top = origin.y;
    windowRect.right = origin.x + size.width;
    windowRect.bottom = origin.y + size.height;

    HMONITOR hMonitor = MonitorFromRect(&windowRect, MONITOR_DEFAULTTONEAREST);

    if (hMonitor == NULL)
      hMonitor = MonitorFromWindow(NULL, MONITOR_DEFAULTTOPRIMARY);

    RECT workAreaRect;
    workAreaRect.left = 0;
    workAreaRect.top = 0;
    workAreaRect.right = 1280;
    workAreaRect.bottom = 1024 - 40; // default Windows 10 task bar height

    if (hMonitor != NULL)
    {
      MONITORINFO monitorInfo = {0};

      monitorInfo.cbSize = sizeof(monitorInfo);

      if (GetMonitorInfoW(hMonitor, &monitorInfo))
      {
        workAreaRect = monitorInfo.rcWork;
      }
    }

    origin.x = workAreaRect.left;
    origin.y = workAreaRect.top;

    size.width = workAreaRect.right - workAreaRect.left;
    size.height = workAreaRect.bottom - workAreaRect.top;
  }

  void FitToWorkArea(Win32Window::Point& origin, Win32Window::Size& size)
  {
    // Retrieve the work area of the monitor that contains or
    // is closed to the supplied window bounds.
    Win32Window::Point workarea_origin = origin;
    Win32Window::Size workarea_size = size;

    GetWorkArea(workarea_origin, workarea_size);

    // Translate the window so that its top/left is inside the work area.
    origin.x = std::max(origin.x, workarea_origin.x);
    origin.y = std::max(origin.y, workarea_origin.y);

    // Crop the window if it extends past the bottom/right of the work area.
    Win32Window::Point workarea_bottom_right(
      workarea_origin.x + workarea_size.width,
      workarea_origin.y + workarea_size.height);

    size.width = std::min(size.width, workarea_bottom_right.x - origin.x);
    size.height = std::min(size.height, workarea_bottom_right.y - origin.y);
  }

  // leapgate: main window sizing (docs/新界面/03-实施方案.md §1.5). The sizes are of the client
  // area, in physical pixels. |frame| is the window size minus the client size, measured on the
  // window: window_manager draws the frame of a hidden title bar itself, so AdjustWindowRect
  // does not know it.

  void GetMonitorWorkArea(HMONITOR monitor, RECT& work, double& scale)
  {
    MONITORINFO info = {0};
    info.cbSize = sizeof(info);
    GetMonitorInfoW(monitor, &info);
    work = info.rcWork;
    scale = FlutterDesktopGetDpiForMonitor(monitor) / 96.0;
  }

  SIZE MinClientSize(const RECT& work, double scale, SIZE frame, const Win32Window::Size& min_size)
  {
    return {std::min(static_cast<LONG>(min_size.width * scale), work.right - work.left - frame.cx),
            std::min(static_cast<LONG>(min_size.height * scale), work.bottom - work.top - frame.cy)};
  }

  SIZE DefaultClientSize(const RECT& work, double scale, SIZE frame,
                         const Win32Window::Size& default_size, const Win32Window::Size& min_size)
  {
    const SIZE min = MinClientSize(work, scale, frame, min_size);
    return {std::max(std::min(static_cast<LONG>(default_size.width * scale),
                              static_cast<LONG>((work.right - work.left) * 0.9)), min.cx),
            std::max(std::min(static_cast<LONG>(default_size.height * scale),
                              static_cast<LONG>((work.bottom - work.top) * 0.9)), min.cy)};
  }

  // Bounds to create the main window with, on the monitor under the cursor. The frame is not known
  // before the window exists and title bar style is set, so FlutterWindow corrects the size to
  // the exact client size when the window is first shown. |origin| comes back in physical screen
  // coordinates, |size| in logical pixels (what Win32Window::CreateAndShow takes).
  void GetMainWindowBounds(const Win32Window::Size& default_size, const Win32Window::Size& min_size,
                           Win32Window::Point& origin, Win32Window::Size& size)
  {
    POINT cursor = {0, 0};
    GetCursorPos(&cursor);
    RECT work;
    double scale;
    GetMonitorWorkArea(MonitorFromPoint(cursor, MONITOR_DEFAULTTOPRIMARY), work, scale);
    const SIZE client = DefaultClientSize(work, scale, {0, 0}, default_size, min_size);
    size.width = static_cast<unsigned int>(client.cx / scale);
    size.height = static_cast<unsigned int>(client.cy / scale);
    origin.x = static_cast<unsigned int>(work.left + (work.right - work.left - client.cx) / 2);
    origin.y = static_cast<unsigned int>(work.top + (work.bottom - work.top - client.cy) / 2);
  }

  bool BumpMouse(int dx, int dy)
  {
    POINT pos;

    if (GetCursorPos(&pos))
    {
      SetCursorPos(pos.x + dx, pos.y + dy);
      return true;
    }

    return false;
  }
}
