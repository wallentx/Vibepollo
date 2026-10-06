/**
 * @file src/platform/linux/display_backend.cpp
 * @brief Linux display backend selection and managed desktop implementation.
 */
#include "display_backend.h"
#include "display_power.h"
#include "private_display.h"
#include "src/rtsp.h"

#include <cstdlib>
#include <display_device/json.h>
#include <string_view>
#include <utility>

#ifdef SUNSHINE_BUILD_GAMESCOPE
  #include "gamescopegrab.h"
#endif

namespace platf::linux_display {
  namespace {
    class hyprland_backend_t final : public backend_t {
    public:
      prepared_display_t prepare_session(rtsp_stream::launch_session_t &session, bool, bool) const override {
        const bool client_requests_virtual = session.client_virtual_display_override.value_or(session.client_requests_virtual_display);
        const bool explicit_physical = session.client_virtual_display_override && !*session.client_virtual_display_override;
        const bool mode_requests_virtual = session.virtual_display_mode_override &&
                                           *session.virtual_display_mode_override != config::video_t::virtual_display_mode_e::disabled;
        bool requests_virtual = session.virtual_display || client_requests_virtual || (mode_requests_virtual && !explicit_physical);
        if (session.output_name_override && !session.output_name_override->empty() && !session.virtual_display && !client_requests_virtual) {
          requests_virtual = false;
        }
        if (requests_virtual) {
          session.virtual_display_failed = true;
          return {false, {}, "Hyprland supports physical display streaming only; select a physical display"};
        }

        if (!session.display_power_guard) {
          session.display_power_guard = display_power::acquire();
        }
        if (!session.display_power_guard) {
          session.virtual_display_failed = true;
          return {false, {}, "The desktop display could not be woken for streaming"};
        }

        session.virtual_display = false;
        session.virtual_display_failed = false;
        session.virtual_display_device_id.clear();
        session.virtual_display_ready_since.reset();
        session.virtual_display_hdr_enabled.reset();
        session.virtual_display_recreated_on_demand = false;
        session.virtual_display_needs_resume_apply = false;
        session.virtual_display_mode_override = config::video_t::virtual_display_mode_e::disabled;
        const auto output_name = session.output_name_override.value_or(config::get_active_output_name());
        return {false, output_name, {}};
      }

      capabilities_t capabilities() const override { return {"hyprland-physical"}; }

      std::optional<display_device::EnumeratedDeviceList> enumerate_devices(display_device::DeviceEnumerationDetail) const override {
        // The privileged capture host has no IPC connection to Hyprland.
        // Capture discovers physical DRM outputs independently.
        return std::nullopt;
      }

      std::string capture_target(const std::string &requested_output) const override {
        return requested_output;
      }
    };

    class desktop_backend_t final : public backend_t {
    public:
      prepared_display_t prepare_session(rtsp_stream::launch_session_t &session, bool no_active_sessions, bool allow_display_changes) const override {
        auto prepared = linux_private_display::prepare_session(session, no_active_sessions, allow_display_changes);
        return {prepared.active, std::move(prepared.output_name), std::move(prepared.error)};
      }

      capabilities_t capabilities() const override {
        return {"kscreen-vkms", linux_private_display::capable(), linux_private_display::ready(), linux_private_display::hdr_capable()};
      }

      std::optional<display_device::EnumeratedDeviceList> enumerate_devices(display_device::DeviceEnumerationDetail detail) const override {
        return linux_private_display::enumerate_devices(detail);
      }

      std::string capture_target(const std::string &requested_output) const override {
        return requested_output;
      }

      bool initialize() const override { return linux_private_display::initialize(); }
      bool apply_session(rtsp_stream::launch_session_t &session) const override { return linux_private_display::apply_session(session); }
      bool revert() const override { return linux_private_display::revert(); }
      bool reset_persistence() const override { return linux_private_display::reset_persistence(); }
      void schedule_revert(std::chrono::milliseconds delay, std::string reason) const override {
        linux_private_display::schedule_revert(delay, std::move(reason));
      }
      void cancel_scheduled_revert() const override { linux_private_display::cancel_scheduled_revert(); }
    };
  }  // namespace

#ifdef SUNSHINE_BUILD_GAMESCOPE
  const backend_t &gamescope_backend();
#endif

  const backend_t &backend() {
#ifdef SUNSHINE_BUILD_GAMESCOPE
    if (gamescope_capture_selected()) {
      return gamescope_backend();
    }
#endif
    // The root-owned supervisor supplies this value from the verified session.
    const auto compositor = std::getenv("VIBEPOLLO_SESSION_COMPOSITOR");
    if (compositor && std::string_view {compositor} == "hyprland") {
      static const hyprland_backend_t hyprland;
      return hyprland;
    }
    static const desktop_backend_t desktop;
    return desktop;
  }

  std::string backend_t::enumerate_devices_json(display_device::DeviceEnumerationDetail detail) const {
    const auto devices = enumerate_devices(detail);
    return devices ? display_device::toJson(*devices, std::nullopt) : "[]";
  }
}  // namespace platf::linux_display
