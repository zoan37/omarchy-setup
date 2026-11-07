// Hyprland exposes libinput's disable-while-typing on/off switch but not its
// timeout, so this plugin sets the timeout on each touchpad.
#include <hyprland/src/plugins/PluginAPI.hpp>
#include <hyprland/src/event/EventBus.hpp>
#include <hyprland/src/managers/input/InputManager.hpp>
#include <hyprland/src/devices/IPointer.hpp>
#include <hyprland/src/version.h>
#include <aquamarine/backend/Session.hpp>

#include <cstdlib>
#include <format>
#include <fstream>
#include <stdexcept>
#include <string>

#include <libinput.h>

static HANDLE              PHANDLE = nullptr;
static CHyprSignalListener g_reloadListener;

// Override with HYPR_DWT_TIMEOUT_MS. Plugin config keys aren't visible to
// Omarchy's Lua config, because plugins load after it is parsed.
static uint32_t timeoutMs() {
    const char* env = std::getenv("HYPR_DWT_TIMEOUT_MS");
    return env ? (uint32_t)std::strtoul(env, nullptr, 10) : 800;
}

static void apply(bool notify) {
    const uint32_t ms = timeoutMs();

    for (const auto& pointer : g_pInputManager->m_pointers) {
        if (!pointer || !pointer->m_isTouchpad || !pointer->aq())
            continue;

        libinput_device* dev = pointer->aq()->getLibinputHandle();
        if (!dev || !libinput_device_config_dwt_is_available(dev))
            continue;

        const uint32_t before = libinput_device_config_dwt_get_timeout(dev);
        const auto     status = libinput_device_config_dwt_set_timeout(dev, ms);
        const uint32_t after  = libinput_device_config_dwt_get_timeout(dev);
        const auto     msg    = std::format("[dwt-timeout] {}: {} ms -> {} ms ({})", pointer->m_deviceName, before, after, libinput_config_status_to_str(status));

        Log::logger->log(Log::INFO, "{}", msg);
        if (const char* dir = std::getenv("XDG_RUNTIME_DIR"))
            std::ofstream(std::string(dir) + "/hypr-dwt-timeout") << msg << "\n";
        if (notify)
            HyprlandAPI::addNotification(PHANDLE, msg, CHyprColor{0.4, 0.7, 1.0, 1.0}, 4000);
    }
}

APICALL EXPORT std::string PLUGIN_API_VERSION() {
    return HYPRLAND_API_VERSION;
}

APICALL EXPORT PLUGIN_DESCRIPTION_INFO PLUGIN_INIT(HANDLE handle) {
    PHANDLE = handle;

    const std::string SERVER = __hyprland_api_get_hash();
    const std::string CLIENT = __hyprland_api_get_client_hash();
    if (SERVER != CLIENT)
        throw std::runtime_error("[dwt-timeout] built for a different Hyprland, rebuild the plugin");

    apply(true);
    g_reloadListener = Event::bus()->m_events.config.reloaded.listen([] { apply(false); });

    return {"hypr-dwt-timeout", "Set libinput's disable-while-typing timeout", "zoan37", "0.1.0"};
}

APICALL EXPORT void PLUGIN_EXIT() {
    g_reloadListener.reset();
}
