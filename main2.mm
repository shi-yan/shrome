#import <Cocoa/Cocoa.h>
#import <Metal/Metal.h>
#import "metal_view.h"
#define UNUSED(x) (void)(x)

#include "include/cef_app.h"
#include "include/cef_client.h"
#include "include/cef_render_handler.h"
#include "include/wrapper/cef_helpers.h"
#include "include/wrapper/cef_library_loader.h"


int main(int argc, const char * argv[]) {
    // Load the CEF library. This is required for macOS.
    CefScopedLibraryLoader library_loader;
    if (!library_loader.LoadInMain())
    {
        return 1;
    }

    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        AppDelegate *delegate = [[AppDelegate alloc] init];
        [app setDelegate:delegate];
        // Create a window
        NSRect windowRect = NSMakeRect(100, 100, 800, 600);
        NSWindow *window = [[NSWindow alloc] 
            initWithContentRect:windowRect
                      styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable
                        backing:NSBackingStoreBuffered
                          defer:NO];
        
        // Create Metal device and Metal view with IME support
        id<MTLDevice> device = MTLCreateSystemDefaultDevice();
        if (!device) {
            NSLog(@"Metal is not supported on this device");
            return -1;
        }
        
        MainMetalView *metalView = [[MainMetalView alloc] initWithFrame:window.contentView.bounds 
                                                              device:device];
        [metalView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
        
        // Add the Metal view to the window
        [window.contentView addSubview:metalView];
        
        // Make the Metal view the first responder for text input
        [window makeFirstResponder:metalView];
        
        // Configure the window
        [window setTitle:@"Metal App with IME Support"];
        [window center];
        [window makeKeyAndOrderFront:nil];
        
        // Set the application activation policy
        [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
           
        // Run the application
        [NSApp run];
    }
    //CefShutdown();
    return 0;
}
