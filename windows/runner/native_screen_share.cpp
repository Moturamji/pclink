#include "native_screen_share.h"

// Windows and GDI+ headers
#include <windows.h>
#include <gdiplus.h>

#include <iostream>
#include <string>

#pragma comment(lib, "gdiplus.lib")
#pragma comment(lib, "gdi32.lib")
#pragma comment(lib, "user32.lib")

namespace pclink {

namespace {

static ULONG_PTR g_gdiplusToken = 0;
static bool g_gdiplusInitialized = false;

int GetEncoderClsid(const WCHAR* format, CLSID* pClsid) {
  UINT num = 0;
  UINT size = 0;
  Gdiplus::GetImageEncodersSize(&num, &size);
  if (size == 0) return -1;

  std::vector<BYTE> memory(size);
  Gdiplus::ImageCodecInfo* pImageCodecInfo =
      reinterpret_cast<Gdiplus::ImageCodecInfo*>(memory.data());
  Gdiplus::GetImageEncoders(num, size, pImageCodecInfo);

  for (UINT j = 0; j < num; ++j) {
    if (wcscmp(pImageCodecInfo[j].MimeType, format) == 0) {
      *pClsid = pImageCodecInfo[j].Clsid;
      return static_cast<int>(j);
    }
  }
  return -1;
}

}  // namespace

void NativeScreenShare::EnsureGdiplusInitialized() {
  if (!g_gdiplusInitialized) {
    Gdiplus::GdiplusStartupInput gdiplusStartupInput;
    Gdiplus::GdiplusStartup(&g_gdiplusToken, &gdiplusStartupInput, NULL);
    g_gdiplusInitialized = true;
  }
}

std::vector<uint8_t> NativeScreenShare::CaptureScreenJpeg(int max_width, int quality) {
  EnsureGdiplusInitialized();

  int screen_w = GetSystemMetrics(SM_CXSCREEN);
  int screen_h = GetSystemMetrics(SM_CYSCREEN);
  if (screen_w <= 0 || screen_h <= 0) {
    return {};
  }

  int target_w = screen_w;
  int target_h = screen_h;
  if (max_width > 0 && screen_w > max_width) {
    target_h = static_cast<int>(
        static_cast<double>(screen_h) * (static_cast<double>(max_width) / static_cast<double>(screen_w)));
    target_w = max_width;
  }

  // Ensure dimensions are even numbers for clean JPEG compression
  if (target_w % 2 != 0) target_w--;
  if (target_h % 2 != 0) target_h--;

  HDC hScreenDC = GetDC(NULL);
  if (!hScreenDC) return {};

  HDC hMemDC = CreateCompatibleDC(hScreenDC);
  if (!hMemDC) {
    ReleaseDC(NULL, hScreenDC);
    return {};
  }

  HBITMAP hBitmap = CreateCompatibleBitmap(hScreenDC, target_w, target_h);
  if (!hBitmap) {
    DeleteDC(hMemDC);
    ReleaseDC(NULL, hScreenDC);
    return {};
  }

  HGDIOBJ hOldBitmap = SelectObject(hMemDC, hBitmap);

  // High-performance hardware/SIMD bilinear downsampling
  // Using SRCCOPY instead of CAPTUREBLT eliminates physical mouse cursor blinking/flickering
  SetStretchBltMode(hMemDC, HALFTONE);
  SetBrushOrgEx(hMemDC, 0, 0, NULL);
  StretchBlt(hMemDC, 0, 0, target_w, target_h, hScreenDC, 0, 0, screen_w, screen_h, SRCCOPY);

  // Draw mouse cursor directly onto the in-memory frame so the phone viewer
  // sees the cursor, while keeping the physical hardware cursor on the PC monitor
  // 100% steady with zero blinking or stuttering.
  CURSORINFO cursor_info = {0};
  cursor_info.cbSize = sizeof(CURSORINFO);
  if (GetCursorInfo(&cursor_info) && cursor_info.flags == CURSOR_SHOWING) {
    ICONINFO icon_info = {0};
    if (GetIconInfo(cursor_info.hCursor, &icon_info)) {
      int cursor_x = cursor_info.ptScreenPos.x - icon_info.xHotspot;
      int cursor_y = cursor_info.ptScreenPos.y - icon_info.yHotspot;

      if (target_w != screen_w && screen_w > 0 && screen_h > 0) {
        cursor_x = static_cast<int>(
            static_cast<double>(cursor_x) * (static_cast<double>(target_w) / static_cast<double>(screen_w)));
        cursor_y = static_cast<int>(
            static_cast<double>(cursor_y) * (static_cast<double>(target_h) / static_cast<double>(screen_h)));
      }

      DrawIconEx(hMemDC, cursor_x, cursor_y, cursor_info.hCursor, 0, 0, 0, NULL, DI_NORMAL);

      if (icon_info.hbmMask) DeleteObject(icon_info.hbmMask);
      if (icon_info.hbmColor) DeleteObject(icon_info.hbmColor);
    }
  }

  // Cleanly deselect bitmap before giving handle to GDI+
  SelectObject(hMemDC, hOldBitmap);
  DeleteDC(hMemDC);
  ReleaseDC(NULL, hScreenDC);

  std::vector<uint8_t> result_bytes;
  {
    // Gdiplus::Bitmap constructor reads HBITMAP in native Windows DIB format
    // ensuring 100% color fidelity (no Blue-Orange channel swap)
    Gdiplus::Bitmap gdi_bitmap(hBitmap, NULL);

    CLSID clsid_jpeg;
    if (GetEncoderClsid(L"image/jpeg", &clsid_jpeg) >= 0) {
      Gdiplus::EncoderParameters encoder_params;
      encoder_params.Count = 1;
      encoder_params.Parameter[0].Guid = Gdiplus::EncoderQuality;
      encoder_params.Parameter[0].Type = Gdiplus::EncoderParameterValueTypeLong;
      encoder_params.Parameter[0].NumberOfValues = 1;
      ULONG qual = static_cast<ULONG>(quality > 0 ? quality : 80);
      encoder_params.Parameter[0].Value = &qual;

      IStream* stream = nullptr;
      if (CreateStreamOnHGlobal(NULL, TRUE, &stream) == S_OK) {
        if (gdi_bitmap.Save(stream, &clsid_jpeg, &encoder_params) == Gdiplus::Ok) {
          STATSTG stat;
          if (stream->Stat(&stat, STATFLAG_NONAME) == S_OK) {
            ULONG size = static_cast<ULONG>(stat.cbSize.QuadPart);
            result_bytes.resize(size);
            LARGE_INTEGER li_zero = {0};
            stream->Seek(li_zero, STREAM_SEEK_SET, NULL);
            ULONG read_bytes = 0;
            stream->Read(result_bytes.data(), size, &read_bytes);
          }
        }
        stream->Release();
      }
    }
  }

  DeleteObject(hBitmap);
  return result_bytes;
}

void NativeScreenShare::RegisterWithMessenger(flutter::BinaryMessenger* messenger) {
  EnsureGdiplusInitialized();

  auto channel = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, "pclink/native_screen_share",
      &flutter::StandardMethodCodec::GetInstance());

  channel->SetMethodCallHandler(
      [](const flutter::MethodCall<flutter::EncodableValue>& call,
         std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        if (call.method_name() == "captureFrame") {
          int max_width = 1920;
          int quality = 85;

          if (call.arguments() && std::holds_alternative<flutter::EncodableMap>(*call.arguments())) {
            const auto& args = std::get<flutter::EncodableMap>(*call.arguments());
            auto mw_it = args.find(flutter::EncodableValue("maxWidth"));
            if (mw_it != args.end() && std::holds_alternative<int>(mw_it->second)) {
              max_width = std::get<int>(mw_it->second);
            }
            auto q_it = args.find(flutter::EncodableValue("quality"));
            if (q_it != args.end() && std::holds_alternative<int>(q_it->second)) {
              quality = std::get<int>(q_it->second);
            }
          }

          auto bytes = CaptureScreenJpeg(max_width, quality);
          if (bytes.empty()) {
            result->Error("CAPTURE_FAILED", "Failed to capture screen frame with Windows GDI");
          } else {
            result->Success(flutter::EncodableValue(bytes));
          }
        } else if (call.method_name() == "isSupported") {
          result->Success(flutter::EncodableValue(true));
        } else {
          result->NotImplemented();
        }
      });

  // Keep channel alive for the lifecycle of the application
  static auto s_channel = std::move(channel);
}

NativeScreenShare::NativeScreenShare() = default;
NativeScreenShare::~NativeScreenShare() = default;

}  // namespace pclink
