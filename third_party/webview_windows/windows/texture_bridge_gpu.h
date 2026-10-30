#pragma once

#include <flutter/texture_registrar.h>

#include "texture_bridge.h"

class TextureBridgeGpu : public TextureBridge {
 public:
  TextureBridgeGpu(GraphicsContext* graphics_context,
                   ABI::Windows::UI::Composition::IVisual* visual);

  const FlutterDesktopGpuSurfaceDescriptor* GetSurfaceDescriptor(size_t width,
                                                                 size_t height);

 protected:
  void StopInternal() override;

 private:
  FlutterDesktopGpuSurfaceDescriptor surface_descriptor_ = {};
  Size surface_size_ = {0, 0};
  winrt::com_ptr<ID3D11Texture2D> surface_{nullptr};
  winrt::com_ptr<IDXGIResource> dxgi_surface_;

  void ProcessFrame(winrt::com_ptr<ID3D11Texture2D> src_texture);
  // True when |surface_| is a usable surface of exactly the requested size. When a new one could
  // not be made this is false and the previous surface (if any) is left as it was.
  bool EnsureSurface(uint32_t width, uint32_t height);
  void ResetDescriptor();
};
