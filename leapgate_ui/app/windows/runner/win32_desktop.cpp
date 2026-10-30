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

  // leapgate: the main window's first-launch bounds (docs/新界面/03-实施方案.md §1.5), in logical
  // pixels: the smaller of 1280x800 and 0.9 x the work area, but not below the minimum, which is
  // the smaller of |min_size| and the work area (as FlutterWindow enforces it). Centered in the
  // work area of the monitor under the cursor; |origin| comes back in physical screen coordinates.
  void GetMainWindowBounds(const Win32Window::Size& min_size, Win32Window::Point& origin, Win32Window::Size& size)
  {
    POINT cursor = {0, 0};
    GetCursorPos(&cursor);
    HMONITOR monitor = MonitorFromPoint(cursor, MONITOR_DEFAULTTOPRIMARY);
    MONITORINFO info = {0};
    info.cbSize = sizeof(info);
    GetMonitorInfoW(monitor, &info);
    const RECT& work = info.rcWork;
    const double scale = FlutterDesktopGetDpiForMonitor(monitor) / 96.0;
    const LONG work_width = work.right - work.left;
    const LONG work_height = work.bottom - work.top;

    const double work_w = work_width / scale;
    const double work_h = work_height / scale;
    size.width = static_cast<unsigned int>(std::max(std::min(1280.0, work_w * 0.9),
                                                    std::min(static_cast<double>(min_size.width), work_w)));
    size.height = static_cast<unsigned int>(std::max(std::min(800.0, work_h * 0.9),
                                                     std::min(static_cast<double>(min_size.height), work_h)));
    origin.x = static_cast<unsigned int>(work.left + (work_width - static_cast<LONG>(size.width * scale)) / 2);
    origin.y = static_cast<unsigned int>(work.top + (work_height - static_cast<LONG>(size.height * scale)) / 2);
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
