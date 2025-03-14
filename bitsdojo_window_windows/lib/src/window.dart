import 'dart:ffi';
import 'dart:ui' as ui;

import 'package:bitsdojo_window_platform_interface/bitsdojo_window_platform_interface.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter/painting.dart';
import 'package:win32/win32.dart';

import './native_api.dart' as native;
import './win32_plus.dart';
import './window_interface.dart';
import './window_util.dart';

var isInsideDoWhenWindowReady = false;

bool isValidHandle(int? handle, String operation) {
  if (handle == null) {
    print("Could not $operation - handle is null");
    return false;
  }
  return true;
}

Rect getScreenRectForWindow(int handle) {
  int monitor = MonitorFromWindow(handle, MONITOR_DEFAULTTONEAREST);
  final monitorInfo = calloc<MONITORINFO>()..ref.cbSize = sizeOf<MONITORINFO>();
  final result = GetMonitorInfo(monitor, monitorInfo);
  if (result == TRUE) {
    return Rect.fromLTRB(monitorInfo.ref.rcWork.left.toDouble(), monitorInfo.ref.rcWork.top.toDouble(),
        monitorInfo.ref.rcWork.right.toDouble(), monitorInfo.ref.rcWork.bottom.toDouble());
  }
  return Rect.zero;
}

class WinWindow extends WinDesktopWindow {
  int? handle;
  ui.Size? _minSize;
  ui.Size? _maxSize;
  // We use this for reporting size inside doWhenWindowReady
  // as GetWindowRect might not work reliably before window is shown on screen
  ui.Size? _sizeSetFromDart;
  Alignment? _alignment;

  void setWindowCutOnMaximize(int value) {
    native.setWindowCutOnMaximize(value);
  }

  WinWindow() {
    _alignment = Alignment.center;
  }

  Rect get rect {
    if (!isValidHandle(handle, "get rectangle")) return Rect.zero;
    final winRect = calloc<RECT>();
    GetWindowRect(handle!, winRect);
    Rect result = winRect.ref.toRect;
    calloc.free(winRect);
    return result;
  }

  set rect(Rect newRect) {
    if (!isValidHandle(handle, "set rectangle")) return;
    setWindowPos(
        handle!, 0, newRect.left.toInt(), newRect.top.toInt(), newRect.width.toInt(), newRect.height.toInt(), 0);
  }

  ui.Size get size {
    final winRect = this.rect;
    final gotSize = getLogicalSize(ui.Size(winRect.width, winRect.height));
    return gotSize;
  }

  ui.Size get sizeOnScreen {
    if (isInsideDoWhenWindowReady == true) {
      if (_sizeSetFromDart != null) {
        final sizeOnScreen = getSizeOnScreen(_sizeSetFromDart!);
        return sizeOnScreen;
      }
    }
    final winRect = this.rect;
    return ui.Size(winRect.width, winRect.height);
  }

  double systemMetric(int metric, {int dpiToUse = 0}) {
    final windowDpi = dpiToUse != 0 ? dpiToUse : this.dpi;
    double result = GetSystemMetricsForDpi(metric, windowDpi).toDouble();
    return result;
  }

  double get borderSize {
    return this.systemMetric(SM_CXBORDER);
  }

  int get dpi {
    if (!isValidHandle(handle, "get dpi")) return 96;
    return GetDpiForWindow(handle!);
  }

  double get scaleFactor {
    double result = this.dpi / 96.0;
    return result;
  }

  double get titleBarHeight {
    double scaleFactor = this.scaleFactor;
    int dpiToUse = this.dpi;
    double cyCaption = systemMetric(SM_CYCAPTION, dpiToUse: dpiToUse);
    cyCaption = (cyCaption / scaleFactor);
    double cySizeFrame = systemMetric(SM_CYSIZEFRAME, dpiToUse: dpiToUse);
    cySizeFrame = (cySizeFrame / scaleFactor);
    double cxPaddedBorder = systemMetric(SM_CXPADDEDBORDER, dpiToUse: dpiToUse);
    cxPaddedBorder = (cxPaddedBorder / scaleFactor).ceilToDouble();
    double result = cySizeFrame + cyCaption + cxPaddedBorder;
    return result;
  }

  ui.Size get titleBarButtonSize {
    double height = this.titleBarHeight - this.borderSize;
    double scaleFactor = this.scaleFactor;
    double cyCaption = systemMetric(SM_CYCAPTION);
    cyCaption /= scaleFactor;
    double width = cyCaption * 2;
    return ui.Size(width, height);
  }

  ui.Size getSizeOnScreen(ui.Size inSize) {
    double scaleFactor = this.scaleFactor;
    double newWidth = inSize.width * scaleFactor;
    double newHeight = inSize.height * scaleFactor;
    return ui.Size(newWidth, newHeight);
  }

  ui.Size getLogicalSize(ui.Size inSize) {
    double scaleFactor = this.scaleFactor;
    double newWidth = inSize.width / scaleFactor;
    double newHeight = inSize.height / scaleFactor;
    return ui.Size(newWidth, newHeight);
  }

  Alignment? get alignment => _alignment;

  /// How the window should be aligned on screen
  set alignment(Alignment? newAlignment) {
    final sizeOnScreen = this.sizeOnScreen;
    _alignment = newAlignment;
    if (_alignment != null) {
      if (!isValidHandle(handle, "set alignment")) return;
      final screenRect = getScreenRectForWindow(handle!);
      final rectOnScreen = getRectOnScreen(sizeOnScreen, _alignment!, screenRect);
      this.rect = rectOnScreen;
    }
  }

  set minSize(ui.Size? newSize) {
    _minSize = newSize;
    if (newSize == null) {
      //TODO - add handling for setting minSize to null
      return;
    }
    native.setMinSize(_minSize!.width.toInt(), _minSize!.height.toInt());
  }

  set maxSize(ui.Size? newSize) {
    _maxSize = newSize;
    if (newSize == null) {
      //TODO - add handling for setting maxSize to null
      return;
    }
    native.setMaxSize(_maxSize!.width.toInt(), _maxSize!.height.toInt());
  }

  set size(ui.Size newSize) {
    if (!isValidHandle(handle, "set size")) return;

    var width = newSize.width;

    if (_minSize != null) {
      if (newSize.width < _minSize!.width) width = _minSize!.width;
    }

    if (_maxSize != null) {
      if (newSize.width > _maxSize!.width) width = _maxSize!.width;
    }

    var height = newSize.height;

    if (_minSize != null) {
      if (newSize.height < _minSize!.height) height = _minSize!.height;
    }

    if (_maxSize != null) {
      if (newSize.height > _maxSize!.height) height = _maxSize!.height;
    }

    ui.Size sizeToSet = ui.Size(width, height);
    _sizeSetFromDart = sizeToSet;
    if (_alignment == null) {
      SetWindowPos(handle!, 0, 0, 0, sizeToSet.width.toInt(), sizeToSet.height.toInt(), SWP_NOMOVE);
    } else {
      final sizeOnScreen = getSizeOnScreen((sizeToSet));
      final screenRect = getScreenRectForWindow(handle!);
      this.rect = getRectOnScreen(sizeOnScreen, _alignment!, screenRect);
    }
  }

  bool get isMaximized {
    if (!isValidHandle(handle, "get isMaximized")) return false;
    return (IsZoomed(handle!) == 1);
  }

  @Deprecated("use isVisible instead")
  bool get visible {
    return isVisible;
  }

  bool get isVisible {
    return (IsWindowVisible(handle!) == 1);
  }

  Offset get position {
    final winRect = this.rect;
    return Offset(winRect.left, winRect.top);
  }

  set position(Offset newPosition) {
    if (!isValidHandle(handle, "set position")) return;
    SetWindowPos(handle!, 0, newPosition.dx.toInt(), newPosition.dy.toInt(), 0, 0, SWP_NOSIZE);
  }

  void show() {
    if (!isValidHandle(handle, "show")) return;
    setWindowPos(handle!, 0, 0, 0, 0, 0, SWP_NOSIZE | SWP_NOMOVE | SWP_SHOWWINDOW);
    forceChildRefresh(handle!);
  }

  void hide() {
    if (!isValidHandle(handle, "hide")) return;
    SetWindowPos(handle!, 0, 0, 0, 0, 0, SWP_NOSIZE | SWP_NOMOVE | SWP_HIDEWINDOW);
  }

  @Deprecated("use show()/hide() instead")
  set visible(bool isVisible) {
    if (isVisible) {
      show();
    } else {
      hide();
    }
  }

  void close() {
    if (!isValidHandle(handle, "close")) return;
    PostMessage(handle!, WM_SYSCOMMAND, SC_CLOSE, 0);
  }

  void maximize() {
    if (!isValidHandle(handle, "maximize")) return;
    PostMessage(handle!, WM_SYSCOMMAND, SC_MAXIMIZE, 0);
  }

  void minimize() {
    if (!isValidHandle(handle, "minimize")) return;

    PostMessage(handle!, WM_SYSCOMMAND, SC_MINIMIZE, 0);
  }

  void restore() {
    if (!isValidHandle(handle, "restore")) return;
    PostMessage(handle!, WM_SYSCOMMAND, SC_RESTORE, 0);
  }

  void maximizeOrRestore() {
    if (!isValidHandle(handle, "maximizeOrRestore")) return;
    if (IsZoomed(handle!) == 1) {
      this.restore();
    } else {
      this.maximize();
    }
  }

  set title(String newTitle) {
    if (!isValidHandle(handle, "set title")) return;
    setWindowText(handle!, newTitle);
  }

  void startDragging() {
    BitsdojoWindowPlatform.instance.dragAppWindow();
  }
}
