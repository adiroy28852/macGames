/* Opens the default render endpoint in shared mode, plays silence for one
 * second and reports how much audio the device consumed. */
#define COBJMACROS
#include <initguid.h>
#include <windows.h>
#include <mmdeviceapi.h>
#include <audioclient.h>
#include <stdio.h>

#define CHECK(x) do { HRESULT hr_ = (x); printf("%-40s 0x%08lx\n", #x, (unsigned long)hr_); if (FAILED(hr_)) return 1; } while (0)

int main(void) {
    IMMDeviceEnumerator *en; IMMDevice *dev; IAudioClient *ac; IAudioRenderClient *rc;
    WAVEFORMATEX *fmt; UINT32 frames, pad; BYTE *buf;
    CoInitializeEx(NULL, COINIT_MULTITHREADED);
    CHECK(CoCreateInstance(&CLSID_MMDeviceEnumerator, NULL, CLSCTX_ALL, &IID_IMMDeviceEnumerator, (void **)&en));
    CHECK(IMMDeviceEnumerator_GetDefaultAudioEndpoint(en, eRender, eConsole, &dev));
    CHECK(IMMDevice_Activate(dev, &IID_IAudioClient, CLSCTX_ALL, NULL, (void **)&ac));
    CHECK(IAudioClient_GetMixFormat(ac, &fmt));
    printf("mix format: %lu Hz, %u ch, %u bits\n", fmt->nSamplesPerSec, fmt->nChannels, fmt->wBitsPerSample);
    CHECK(IAudioClient_Initialize(ac, AUDCLNT_SHAREMODE_SHARED, 0, 2000000, 0, fmt, NULL));
    CHECK(IAudioClient_GetBufferSize(ac, &frames));
    CHECK(IAudioClient_GetService(ac, &IID_IAudioRenderClient, (void **)&rc));
    CHECK(IAudioRenderClient_GetBuffer(rc, frames, &buf));
    CHECK(IAudioRenderClient_ReleaseBuffer(rc, frames, AUDCLNT_BUFFERFLAGS_SILENT));
    CHECK(IAudioClient_Start(ac));
    Sleep(1000);
    CHECK(IAudioClient_GetCurrentPadding(ac, &pad));
    printf("buffer %u frames, consumed in 1s: %u frames\n", frames, frames - pad);
    return 0;
}
