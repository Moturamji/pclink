#ifndef RUNNER_NATIVE_SCREEN_SHARE_H_
#define RUNNER_NATIVE_SCREEN_SHARE_H_

#include <flutter/binary_messenger.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <memory>
#include <vector>

namespace pclink {

class NativeScreenShare {
 public:
  static void RegisterWithMessenger(flutter::BinaryMessenger* messenger);

  NativeScreenShare();
  ~NativeScreenShare();

  static std::vector<uint8_t> CaptureScreenJpeg(int max_width, int quality);

 private:
  static void EnsureGdiplusInitialized();
};

}  // namespace pclink

#endif  // RUNNER_NATIVE_SCREEN_SHARE_H_
