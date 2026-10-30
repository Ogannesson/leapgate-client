// 上游：flutter/windows/runner/flutter_window.h@bd9262397（复制后修改）
#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>

#include <memory>

#include "win32_window.h"

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

  // leapgate: makes this the main window, sized by its client area in logical pixels: the window
  // gets |default_size| (capped by the work area) when first shown, and can't be made smaller
  // than |min_size| (capped likewise). Call before CreateAndShow.
  void SetClientSizes(const Size& default_size, const Size& min_size);

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

  // Whether the engine has generated its first frame. Note that a generated
  // frame is not necessarily presented: the resize synchronization may reject
  // it (see kForceRedrawTimerId in the .cpp file).
  bool first_frame_rendered_ = false;

  // Number of force-redraw attempts made so far.
  UINT force_redraw_tries_ = 0;

  void ApplyDefaultClientSize(HWND hwnd);

  unsigned int default_width_ = 0;
  unsigned int default_height_ = 0;
  unsigned int min_width_ = 0;
  unsigned int min_height_ = 0;
  bool default_size_applied_ = false;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
