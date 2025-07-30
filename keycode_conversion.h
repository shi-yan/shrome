#ifndef KEYCODE_CONVERSION_H
#define KEYCODE_CONVERSION_H

#include <tuple>
#include <SDL3/SDL.h>

#include "include/wrapper/cef_helpers.h"
#include "include/wrapper/cef_library_loader.h"

std::tuple<int, int, char16_t> keycode_conversion(const SDL_KeyboardEvent &keyboard_event);

uint16_t sdl_keycode_2_mac_keycode(int sdl_keycode);

void debug_print_cef_key_event(const CefKeyEvent &key_event);

bool is_modifier_key(const SDL_KeyboardEvent &keyboard_event);

bool should_skip_key_up(const SDL_KeyboardEvent &keyboard_event);

#endif // KEYCODE_CONVERSION_H
