#ifndef KEYCODE_CONVERSION_H
#define KEYCODE_CONVERSION_H

#include <tuple>
#include <SDL3/SDL.h>

std::tuple<int, int, char16_t> keycode_conversion(const SDL_KeyboardEvent &keyboard_event);

uint16_t sdl_keycode_2_mac_keycode(int sdl_keycode);



#endif // KEYCODE_CONVERSION_H
