#include "keycode_conversion.h"
#include "mac_keycode.h"
#include "win_keycode.h"
#include <iostream>

bool is_modifier_key(const SDL_KeyboardEvent &keyboard_event)
{
    switch (keyboard_event.key)
    {
    case SDLK_LCTRL:
    case SDLK_RCTRL:
    case SDLK_LSHIFT:
    case SDLK_RSHIFT:
    case SDLK_LALT:
    case SDLK_RALT:
    case SDLK_LGUI:
    case SDLK_RGUI:
    case SDLK_CAPSLOCK:
        return true;
    default:
        return false;
    }
}

bool should_skip_key_up(const SDL_KeyboardEvent &keyboard_event)
{
    switch (keyboard_event.key)
    {
    case SDLK_LEFT:
    case SDLK_RIGHT:
    case SDLK_UP:
    case SDLK_DOWN:
        return true;
    default:
        return false;
    }
}

std::tuple<int, int, char16_t> keycode_conversion(const SDL_KeyboardEvent &keyboard_event)
{
    int key_code = keyboard_event.key;
    int scan_code = keyboard_event.scancode;
    char16_t character = 0;
    std::cout << "debug keycode 0x" << std::hex << key_code << std::endl;
    switch (key_code)
    {
    case SDLK_A:
        if (keyboard_event.mod & SDL_KMOD_SHIFT)
        {
            return {0, sdl_keycode_2_mac_keycode(key_code), 'A'};
        }
        else
        {
            return {0, sdl_keycode_2_mac_keycode(key_code), 'a'};
        }
    case SDLK_S:
        if (keyboard_event.mod & SDL_KMOD_SHIFT)
        {
            return {0, sdl_keycode_2_mac_keycode(key_code), 'S'};
        }
        else
        {
            return {0, sdl_keycode_2_mac_keycode(key_code), 's'};
        }
    case SDLK_D:
        if (keyboard_event.mod & SDL_KMOD_SHIFT)
        {
            return {0, sdl_keycode_2_mac_keycode(key_code), 'D'};
        }
        else
        {
            return {0, sdl_keycode_2_mac_keycode(key_code), 'd'};
        }
    case SDLK_F:
        if (keyboard_event.mod & SDL_KMOD_SHIFT)
        {
            return {0, sdl_keycode_2_mac_keycode(key_code), 'F'};
        }
        else
        {
            return {0, sdl_keycode_2_mac_keycode(key_code), 'f'};
        }
    case SDLK_H:
        if (keyboard_event.mod & SDL_KMOD_SHIFT)
        {
            return {0, sdl_keycode_2_mac_keycode(key_code), 'H'};
        }
        else
        {
            return {0, sdl_keycode_2_mac_keycode(key_code), 'h'};
        }
    case SDLK_G:
        if (keyboard_event.mod & SDL_KMOD_SHIFT)
        {
            return {0, sdl_keycode_2_mac_keycode(key_code), 'G'};
        }
        else
        {
            return {0, sdl_keycode_2_mac_keycode(key_code), 'g'};
        }
    case SDLK_Z:
        if (keyboard_event.mod & SDL_KMOD_SHIFT)
        {
            return {0, sdl_keycode_2_mac_keycode(key_code), 'Z'};
        }
        else
        {
            return {0, sdl_keycode_2_mac_keycode(key_code), 'z'};
        }
    case SDLK_X:
        if (keyboard_event.mod & SDL_KMOD_SHIFT)
        {
            return {0, sdl_keycode_2_mac_keycode(key_code), 'X'};
        }
        else
        {
            return {0, sdl_keycode_2_mac_keycode(key_code), 'x'};
        }
    case SDLK_C:
        if (keyboard_event.mod & SDL_KMOD_SHIFT)
        {
            return {0, sdl_keycode_2_mac_keycode(key_code), 'C'};
        }
        else
        {
            return {0, sdl_keycode_2_mac_keycode(key_code), 'c'};
        }
    case SDLK_V:
        if (keyboard_event.mod & SDL_KMOD_SHIFT)
        {
            return {0, sdl_keycode_2_mac_keycode(key_code), 'V'};
        }
        else
        {
            return {0, sdl_keycode_2_mac_keycode(key_code), 'v'};
        }
    case SDLK_B:
        if (keyboard_event.mod & SDL_KMOD_SHIFT)
        {
            return {0, sdl_keycode_2_mac_keycode(key_code), 'B'};
        }
        else
        {
            return {0, sdl_keycode_2_mac_keycode(key_code), 'b'};
        }
    case SDLK_Q:
        if (keyboard_event.mod & SDL_KMOD_SHIFT)
        {
            return {0, sdl_keycode_2_mac_keycode(key_code), 'Q'};
        }
        else
        {
            return {0, sdl_keycode_2_mac_keycode(key_code), 'q'};
        }
    case SDLK_W:
        if (keyboard_event.mod & SDL_KMOD_SHIFT)
        {
            return {0, sdl_keycode_2_mac_keycode(key_code), 'W'};
        }
        else
        {
            return {0, sdl_keycode_2_mac_keycode(key_code), 'w'};
        }
    case SDLK_E:
        if (keyboard_event.mod & SDL_KMOD_SHIFT)
        {
            return {0, sdl_keycode_2_mac_keycode(key_code), 'E'};
        }
        else
        {
            return {0, sdl_keycode_2_mac_keycode(key_code), 'e'};
        }
    case SDLK_R:
        if (keyboard_event.mod & SDL_KMOD_SHIFT)
        {
            return {0, sdl_keycode_2_mac_keycode(key_code), 'R'};
        }
        else
        {
            return {0, sdl_keycode_2_mac_keycode(key_code), 'r'};
        }
    case SDLK_Y:
        if (keyboard_event.mod & SDL_KMOD_SHIFT)
        {
            return {0, sdl_keycode_2_mac_keycode(key_code), 'Y'};
        }
        else
        {
            return {0, sdl_keycode_2_mac_keycode(key_code), 'y'};
        }
    case SDLK_T:
        if (keyboard_event.mod & SDL_KMOD_SHIFT)
        {
            return {0, sdl_keycode_2_mac_keycode(key_code), 'T'};
        }
        else
        {
            return {0, sdl_keycode_2_mac_keycode(key_code), 't'};
        }
    case SDLK_1:
        if (keyboard_event.mod & SDL_KMOD_SHIFT)
        {
            return {0, sdl_keycode_2_mac_keycode(key_code), '!'};
        }
        else
        {
            return {0, sdl_keycode_2_mac_keycode(key_code), '1'};
        }
    case SDLK_2:
        if (keyboard_event.mod & SDL_KMOD_SHIFT)
        {
            return {0, sdl_keycode_2_mac_keycode(key_code), '@'};
        }
        else
        {
            return {0, sdl_keycode_2_mac_keycode(key_code), '2'};
        }
    case SDLK_3:
        if (keyboard_event.mod & SDL_KMOD_SHIFT)
        {
            return {0, sdl_keycode_2_mac_keycode(key_code), '#'};
        }
        else
        {
            return {0, sdl_keycode_2_mac_keycode(key_code), '3'};
        }

    case SDLK_4:
        if (keyboard_event.mod & SDL_KMOD_SHIFT)
        {
            return {0, sdl_keycode_2_mac_keycode(key_code), '$'};
        }
        else
        {
            return {0, sdl_keycode_2_mac_keycode(key_code), '4'};
        }

    case SDLK_6:
        if (keyboard_event.mod & SDL_KMOD_SHIFT)
        {
            return {0, sdl_keycode_2_mac_keycode(key_code), '^'};
        }
        else
        {
            return {0, sdl_keycode_2_mac_keycode(key_code), '6'};
        }
    case SDLK_5:
        if (keyboard_event.mod & SDL_KMOD_SHIFT)
        {
            return {0, sdl_keycode_2_mac_keycode(key_code), '%'};
        }
        else
        {
            return {0, sdl_keycode_2_mac_keycode(key_code), '5'};
        }

    case SDLK_EQUALS:
        if (keyboard_event.mod & SDL_KMOD_SHIFT)
        {
            return {0, sdl_keycode_2_mac_keycode(key_code), '+'};
        }
        else
        {
            return {0, sdl_keycode_2_mac_keycode(key_code), '='};
        }

    case SDLK_9:
        if (keyboard_event.mod & SDL_KMOD_SHIFT)
        {
            return {0, sdl_keycode_2_mac_keycode(key_code), '('};
        }
        else
        {
            return {0, sdl_keycode_2_mac_keycode(key_code), '9'};
        }

    case SDLK_7:
        if (keyboard_event.mod & SDL_KMOD_SHIFT)
        {
            return {0, sdl_keycode_2_mac_keycode(key_code), '&'};
        }
        else
        {
            return {0, sdl_keycode_2_mac_keycode(key_code), '7'};
        }

    case SDLK_MINUS:
        if (keyboard_event.mod & SDL_KMOD_SHIFT)
        {
            return {0, sdl_keycode_2_mac_keycode(key_code), '_'};
        }
        else
        {
            return {0, sdl_keycode_2_mac_keycode(key_code), '-'};
        }

    case SDLK_8:
        if (keyboard_event.mod & SDL_KMOD_SHIFT)
        {
            return {0, sdl_keycode_2_mac_keycode(key_code), '*'};
        }
        else
        {
            return {0, sdl_keycode_2_mac_keycode(key_code), '8'};
        }

    case SDLK_0:
        if (keyboard_event.mod & SDL_KMOD_SHIFT)
        {
            return {0, sdl_keycode_2_mac_keycode(key_code), ')'};
        }
        else
        {
            return {0, sdl_keycode_2_mac_keycode(key_code), '0'};
        }

    case SDLK_RIGHTBRACKET:
        if (keyboard_event.mod & SDL_KMOD_SHIFT)
        {
            return {0, sdl_keycode_2_mac_keycode(key_code), '}'};
        }
        else
        {
            return {0, sdl_keycode_2_mac_keycode(key_code), ']'};
        }
    case SDLK_O:
        if (keyboard_event.mod & SDL_KMOD_SHIFT)
        {
            return {0, sdl_keycode_2_mac_keycode(key_code), 'O'};
        }
        else
        {
            return {0, sdl_keycode_2_mac_keycode(key_code), 'o'};
        }
    case SDLK_U:
        if (keyboard_event.mod & SDL_KMOD_SHIFT)
        {
            return {0, sdl_keycode_2_mac_keycode(key_code), 'U'};
        }
        else
        {
            return {0, sdl_keycode_2_mac_keycode(key_code), 'u'};
        }
    case SDLK_LEFTBRACKET:
        if (keyboard_event.mod & SDL_KMOD_SHIFT)
        {
            return {0, sdl_keycode_2_mac_keycode(key_code), '{'};
        }
        else
        {
            return {0, sdl_keycode_2_mac_keycode(key_code), '['};
        }
    case SDLK_I:
        if (keyboard_event.mod & SDL_KMOD_SHIFT)
        {
            return {0, sdl_keycode_2_mac_keycode(key_code), 'I'};
        }
        else
        {
            return {0, sdl_keycode_2_mac_keycode(key_code), 'i'};
        }
    case SDLK_P:
        if (keyboard_event.mod & SDL_KMOD_SHIFT)
        {
            return {0, sdl_keycode_2_mac_keycode(key_code), 'P'};
        }
        else
        {
            return {0, sdl_keycode_2_mac_keycode(key_code), 'p'};
        }
    case SDLK_L:
        if (keyboard_event.mod & SDL_KMOD_SHIFT)
        {
            return {0, sdl_keycode_2_mac_keycode(key_code), 'L'};
        }
        else
        {
            return {0, sdl_keycode_2_mac_keycode(key_code), 'l'};
        }
    case SDLK_J:
        if (keyboard_event.mod & SDL_KMOD_SHIFT)
        {
            return {0, sdl_keycode_2_mac_keycode(key_code), 'J'};
        }
        else
        {
            return {0, sdl_keycode_2_mac_keycode(key_code), 'j'};
        }
    case SDLK_APOSTROPHE:
        if (keyboard_event.mod & SDL_KMOD_SHIFT)
        {
            return {0, sdl_keycode_2_mac_keycode(key_code), '"'};
        }
        else
        {
            return {0, sdl_keycode_2_mac_keycode(key_code), '\''};
        }
    case SDLK_K:
        if (keyboard_event.mod & SDL_KMOD_SHIFT)
        {
            return {0, sdl_keycode_2_mac_keycode(key_code), 'K'};
        }
        else
        {
            return {0, sdl_keycode_2_mac_keycode(key_code), 'k'};
        }
    case SDLK_SEMICOLON:
        if (keyboard_event.mod & SDL_KMOD_SHIFT)
        {
            return {0, sdl_keycode_2_mac_keycode(key_code), ':'};
        }
        else
        {
            return {0, sdl_keycode_2_mac_keycode(key_code), ';'};
        }
    case SDLK_BACKSLASH:
        if (keyboard_event.mod & SDL_KMOD_SHIFT)
        {
            return {0, sdl_keycode_2_mac_keycode(key_code), '|'};
        }
        else
        {
            return {0, sdl_keycode_2_mac_keycode(key_code), '\\'};
        }
    case SDLK_COMMA:
        if (keyboard_event.mod & SDL_KMOD_SHIFT)
        {
            return {0, sdl_keycode_2_mac_keycode(key_code), '<'};
        }
        else
        {
            return {0, sdl_keycode_2_mac_keycode(key_code), ','};
        }
    case SDLK_SLASH:
        if (keyboard_event.mod & SDL_KMOD_SHIFT)
        {
            return {0, sdl_keycode_2_mac_keycode(key_code), '?'};
        }
        else
        {
            return {0, sdl_keycode_2_mac_keycode(key_code), '/'};
        }
    case SDLK_N:
        if (keyboard_event.mod & SDL_KMOD_SHIFT)
        {
            return {0, sdl_keycode_2_mac_keycode(key_code), 'N'};
        }
        else
        {
            return {0, sdl_keycode_2_mac_keycode(key_code), 'n'};
        }
    case SDLK_M:
        if (keyboard_event.mod & SDL_KMOD_SHIFT)
        {
            return {0, sdl_keycode_2_mac_keycode(key_code), 'M'};
        }
        else
        {
            return {0, sdl_keycode_2_mac_keycode(key_code), 'm'};
        }
    case SDLK_PERIOD:
        if (keyboard_event.mod & SDL_KMOD_SHIFT)
        {
            return {0, sdl_keycode_2_mac_keycode(key_code), '>'};
        }
        else
        {
            return {0, sdl_keycode_2_mac_keycode(key_code), '.'};
        }
    case SDLK_GRAVE:
        if (keyboard_event.mod & SDL_KMOD_SHIFT)
        {
            return {0, sdl_keycode_2_mac_keycode(key_code), '~'};
        }
        else
        {
            return {0, sdl_keycode_2_mac_keycode(key_code), '`'};
        }
    case SDLK_KP_PERIOD:
        return {0, sdl_keycode_2_mac_keycode(key_code), '.'};
    case SDLK_KP_MULTIPLY:
        return {0, sdl_keycode_2_mac_keycode(key_code), '*'};
    case SDLK_KP_PLUS:
        return {0, sdl_keycode_2_mac_keycode(key_code), '+'};
    case SDLK_RETURN:
        return {0, sdl_keycode_2_mac_keycode(key_code), '\n'};
    case SDLK_BACKSPACE:
        return {0, sdl_keycode_2_mac_keycode(key_code), '\b'};
    case SDLK_LSHIFT:
        return {0, sdl_keycode_2_mac_keycode(key_code), 0};
    case SDLK_LEFT:
        return {0, sdl_keycode_2_mac_keycode(key_code), 0};
    case SDLK_RIGHT:
        return {0, sdl_keycode_2_mac_keycode(key_code), 0};
    case SDLK_UP:
        return {0, sdl_keycode_2_mac_keycode(key_code), 0};
    case SDLK_DOWN:
        return {0, sdl_keycode_2_mac_keycode(key_code), 0};
    case SDLK_SPACE:
        return {0, sdl_keycode_2_mac_keycode(key_code), ' '};
    default:
        return {key_code, scan_code, character};
    }
}

uint16_t sdl_keycode_2_mac_keycode(int sdl_keycode)
{
    switch (sdl_keycode)
    {
    case SDLK_A:
        return kVK_ANSI_A;
    case SDLK_S:
        return kVK_ANSI_S;
    case SDLK_D:
        return kVK_ANSI_D;
    case SDLK_F:
        return kVK_ANSI_F;
    case SDLK_H:
        return kVK_ANSI_H;
    case SDLK_G:
        return kVK_ANSI_G;
    case SDLK_Z:
        return kVK_ANSI_Z;
    case SDLK_X:
        return kVK_ANSI_X;
    case SDLK_C:
        return kVK_ANSI_C;
    case SDLK_V:
        return kVK_ANSI_V;
    case SDLK_B:
        return kVK_ANSI_B;
    case SDLK_Q:
        return kVK_ANSI_Q;
    case SDLK_W:
        return kVK_ANSI_W;
    case SDLK_E:
        return kVK_ANSI_E;
    case SDLK_R:
        return kVK_ANSI_R;
    case SDLK_Y:
        return kVK_ANSI_Y;
    case SDLK_T:
        return kVK_ANSI_T;
    case SDLK_1:
        return kVK_ANSI_1;
    case SDLK_2:
        return kVK_ANSI_2;
    case SDLK_3:
        return kVK_ANSI_3;
    case SDLK_4:
        return kVK_ANSI_4;
    case SDLK_6:
        return kVK_ANSI_6;
    case SDLK_5:
        return kVK_ANSI_5;
    case SDLK_EQUALS:
        return kVK_ANSI_Equal;
    case SDLK_9:
        return kVK_ANSI_9;
    case SDLK_7:
        return kVK_ANSI_7;
    case SDLK_MINUS:
        return kVK_ANSI_Minus;
    case SDLK_8:
        return kVK_ANSI_8;
    case SDLK_0:
        return kVK_ANSI_0;
    case SDLK_RIGHTBRACKET:
        return kVK_ANSI_RightBracket;
    case SDLK_O:
        return kVK_ANSI_O;
    case SDLK_U:
        return kVK_ANSI_U;
    case SDLK_LEFTBRACKET:
        return kVK_ANSI_LeftBracket;
    case SDLK_I:
        return kVK_ANSI_I;
    case SDLK_P:
        return kVK_ANSI_P;
    case SDLK_L:
        return kVK_ANSI_L;
    case SDLK_J:
        return kVK_ANSI_J;
    case SDLK_APOSTROPHE:
        return kVK_ANSI_Quote;
    case SDLK_K:
        return kVK_ANSI_K;
    case SDLK_SEMICOLON:
        return kVK_ANSI_Semicolon;
    case SDLK_BACKSLASH:
        return kVK_ANSI_Backslash;
    case SDLK_COMMA:
        return kVK_ANSI_Comma;
    case SDLK_SLASH:
        return kVK_ANSI_Slash;
    case SDLK_N:
        return kVK_ANSI_N;
    case SDLK_M:
        return kVK_ANSI_M;
    case SDLK_PERIOD:
        return kVK_ANSI_Period;
    case SDLK_GRAVE:
        return kVK_ANSI_Grave;
    case SDLK_KP_PERIOD:
        return kVK_ANSI_KeypadDecimal;
    case SDLK_KP_MULTIPLY:
        return kVK_ANSI_KeypadMultiply;
    case SDLK_KP_PLUS:
        return kVK_ANSI_KeypadPlus;
    case SDLK_KP_CLEAR:
        return kVK_ANSI_KeypadClear;
    case SDLK_KP_DIVIDE:
        return kVK_ANSI_KeypadDivide;
    case SDLK_KP_ENTER:
        return kVK_ANSI_KeypadEnter;
    case SDLK_KP_MINUS:
        return kVK_ANSI_KeypadMinus;
    case SDLK_KP_EQUALS:
        return kVK_ANSI_KeypadEquals;
    case SDLK_KP_0:
        return kVK_ANSI_Keypad0;
    case SDLK_KP_1:
        return kVK_ANSI_Keypad1;
    case SDLK_KP_2:
        return kVK_ANSI_Keypad2;
    case SDLK_KP_3:
        return kVK_ANSI_Keypad3;
    case SDLK_KP_4:
        return kVK_ANSI_Keypad4;
    case SDLK_KP_5:
        return kVK_ANSI_Keypad5;
    case SDLK_KP_6:
        return kVK_ANSI_Keypad6;
    case SDLK_KP_7:
        return kVK_ANSI_Keypad7;
    case SDLK_KP_8:
        return kVK_ANSI_Keypad8;
    case SDLK_KP_9:
        return kVK_ANSI_Keypad9;

    case SDLK_RETURN:
        return kVK_Return;
    case SDLK_TAB:
        return kVK_Tab;
    case SDLK_SPACE:
        return kVK_Space;
    case SDLK_DELETE:
        return kVK_Delete;
    case SDLK_BACKSPACE:
        return kVK_Delete; // Backspace is mapped to Delete on macOS
    case SDLK_ESCAPE:
        return kVK_Escape;
    case SDLK_LGUI:
        return kVK_Command;
    case SDLK_LSHIFT:
        return kVK_Shift;
    case SDLK_CAPSLOCK:
        return kVK_CapsLock;
    case SDLK_LALT:
        return kVK_Option;
    case SDLK_LCTRL:
        return kVK_Control;
    case SDLK_RSHIFT:
        return kVK_RightShift;
    case SDLK_RALT:
        return kVK_RightOption;
    case SDLK_RCTRL:
        return kVK_RightControl;

    /*case sdlk_fn:
        return kVK_Function;*/
    case SDLK_F17:
        return kVK_F17;
    case SDLK_VOLUMEUP:
        return kVK_VolumeUp;
    case SDLK_VOLUMEDOWN:
        return kVK_VolumeDown;
    case SDLK_MUTE:
        return kVK_Mute;
    case SDLK_F18:
        return kVK_F18;
    case SDLK_F19:
        return kVK_F19;
    case SDLK_F20:
        return kVK_F20;
    case SDLK_F5:
        return kVK_F5;
    case SDLK_F6:
        return kVK_F6;
    case SDLK_F7:
        return kVK_F7;
    case SDLK_F3:
        return kVK_F3;
    case SDLK_F8:
        return kVK_F8;
    case SDLK_F9:
        return kVK_F9;
    case SDLK_F11:
        return kVK_F11;
    case SDLK_F13:
        return kVK_F13;
    case SDLK_F16:
        return kVK_F16;

    case SDLK_F14:
        return kVK_F14;
    case SDLK_F10:
        return kVK_F10;
    case SDLK_F12:
        return kVK_F12;
    case SDLK_F15:
        return kVK_F15;
    case SDLK_HELP:
        return kVK_Help;
    case SDLK_HOME:
        return kVK_Home;
    case SDLK_PAGEUP:
        return kVK_PageUp;
        /* case SDLK_ForwardDelete:
             return kVK_ForwardDelete;*/
    case SDLK_F4:
        return kVK_F4;
    case SDLK_END:
        return kVK_End;
    case SDLK_F2:
        return kVK_F2;
    case SDLK_PAGEDOWN:
        return kVK_PageDown;
    case SDLK_F1:
        return kVK_F1;
    case SDLK_LEFT:
        return kVK_LeftArrow;
    case SDLK_RIGHT:
        return kVK_RightArrow;
    case SDLK_DOWN:
        return kVK_DownArrow;
    case SDLK_UP:
        return kVK_UpArrow;

    default:
        break;
    }
    return 0;
}

void debug_print_cef_key_event(const CefKeyEvent &key_event)
{
    switch (key_event.type)
    {
    case KEYEVENT_RAWKEYDOWN:
        std::cout << "CEF_KeyEvent: RAWKEYDOWN =====" << std::endl;
        break;
    case KEYEVENT_KEYDOWN:
        std::cout << "CEF_KeyEvent: KEYDOWN =====" << std::endl;
        break;
    case KEYEVENT_KEYUP:
        std::cout << "CEF_KeyEvent: KEYUP =====" << std::endl;
        break;
    case KEYEVENT_CHAR:
        std::cout << "CEF_KeyEvent: CHAR =====" << std::endl;
        break;
    }
    std::cout << "virtual keycode: (0x" << std::hex << key_event.windows_key_code << std::dec << ")" << std::endl
              << "native_key_code: " << key_event.native_key_code << std::endl
              << "character: " << key_event.character << std::endl
              << "unmodified_character: " << key_event.unmodified_character << std::endl
              << "modifiers: " << key_event.modifiers << std::endl
              << "is_system_key: " << key_event.is_system_key << std::endl
              << "focus_on_editable_field: " << key_event.focus_on_editable_field << std::endl;
    std::cout << "========================" << std::endl;
}
