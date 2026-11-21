#include <initguid.h>
#define COBJMACROS
#define INITGUID
#include <windows.h>
#include <dxgi1_4.h>
#include <d3d12.h>
#include <stdio.h>

int main(void) {
    setvbuf(stdout, NULL, _IONBF, 0);  /* D3DMetal can end the process before stdio flushes */
    IDXGIFactory4 *factory = NULL;
    HRESULT hr = CreateDXGIFactory1(&IID_IDXGIFactory4, (void**)&factory);
    printf("CreateDXGIFactory1: 0x%08lx\n", (unsigned long)hr);
    if (FAILED(hr)) return 1;

    IDXGIAdapter1 *adapter = NULL;
    for (UINT i = 0; factory->lpVtbl->EnumAdapters1(factory, i, &adapter) != DXGI_ERROR_NOT_FOUND; i++) {
        DXGI_ADAPTER_DESC1 desc;
        adapter->lpVtbl->GetDesc1(adapter, &desc);
        printf("Adapter %u: %ls (vendor 0x%04x, dedVram %lluMB, flags 0x%x)\n",
               i, desc.Description, desc.VendorId,
               (unsigned long long)(desc.DedicatedVideoMemory >> 20), desc.Flags);

        ID3D12Device *dev = NULL;
        D3D_FEATURE_LEVEL levels[] = { D3D_FEATURE_LEVEL_12_1, D3D_FEATURE_LEVEL_12_0, D3D_FEATURE_LEVEL_11_0 };
        for (int l = 0; l < 3; l++) {
            hr = D3D12CreateDevice((IUnknown*)adapter, levels[l], &IID_ID3D12Device, (void**)&dev);
            if (SUCCEEDED(hr)) {
                printf("  D3D12CreateDevice OK at feature level 0x%x\n", levels[l]);
                dev->lpVtbl->Release(dev);
                break;
            }
        }
        if (FAILED(hr)) printf("  D3D12CreateDevice FAILED: 0x%08lx\n", (unsigned long)hr);
        adapter->lpVtbl->Release(adapter);
    }
    factory->lpVtbl->Release(factory);
    return 0;
}