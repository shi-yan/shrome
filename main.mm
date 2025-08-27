#import <Cocoa/Cocoa.h>
#import <Metal/Metal.h>
#import "metal_view.h"
#define UNUSED(x) (void)(x)

#include "include/cef_app.h"
#include "include/cef_client.h"
#import "include/cef_application_mac.h"
#import "include/cef_id_mappers.h"
#import "include/wrapper/cef_library_loader.h"
#include "include/cef_render_handler.h"
#include "include/wrapper/cef_helpers.h"
#include "include/wrapper/cef_library_loader.h"


@interface WindowDelegate: NSObject <NSWindowDelegate>
@property (weak, nonatomic) MainMetalView *metalView;
@end


@implementation WindowDelegate

- (BOOL) windowShouldClose: (NSWindow *) window {
  NSLog(@"Window should close - cleaning up MetalView");
  //if (self.metalView) {
  //  [self.metalView cleanup];
 // }
  return YES;
}

-(void) windowWillClose: (NSNotification *)notification {
  NSLog(@"Window will close");
  if (self.metalView) {
    [self.metalView cleanup];
  }
}

@end

// Provide the CefAppProtocol implementation required by CEF.
@interface ClientApplication : NSApplication <CefAppProtocol> {
    @private
     BOOL handlingSendEvent_;
   }
   @end
   
   @implementation ClientApplication
   
   - (BOOL)isHandlingSendEvent {
     return handlingSendEvent_;
   }
   
   - (void)setHandlingSendEvent:(BOOL)handlingSendEvent {
     handlingSendEvent_ = handlingSendEvent;
   }
   
   - (void)sendEvent:(NSEvent*)event {
     CefScopedSendingEvent sendingEventScoper;
     [super sendEvent:event];
   }
   
   // |-terminate:| is the entry point for orderly "quit" operations in Cocoa. This
   // includes the application menu's quit menu item and keyboard equivalent, the
   // application's dock icon menu's quit menu item, "quit" (not "force quit") in
   // the Activity Monitor, and quits triggered by user logout and system restart
   // and shutdown.
   //
   // The default |-terminate:| implementation ends the process by calling exit(),
   // and thus never leaves the main run loop. This is unsuitable for Chromium
   // since Chromium depends on leaving the main run loop to perform an orderly
   // shutdown. We support the normal |-terminate:| interface by overriding the
   // default implementation. Our implementation, which is very specific to the
   // needs of Chromium, works by asking the application delegate to terminate
   // using its |-tryToTerminateApplication:| method.
   //
   // |-tryToTerminateApplication:| differs from the standard
   // |-applicationShouldTerminate:| in that no special event loop is run in the
   // case that immediate termination is not possible (e.g., if dialog boxes
   // allowing the user to cancel have to be shown). Instead, this method tries to
   // close all browsers by calling CloseBrowser(false) via
   // ClientHandler::CloseAllBrowsers. Calling CloseBrowser will result in a call
   // to ClientHandler::DoClose and execution of |-performClose:| on the NSWindow.
   // DoClose sets a flag that is used to differentiate between new close events
   // (e.g., user clicked the window close button) and in-progress close events
   // (e.g., user approved the close window dialog). The NSWindowDelegate
   // |-windowShouldClose:| method checks this flag and either calls
   // CloseBrowser(false) in the case of a new close event or destructs the
   // NSWindow in the case of an in-progress close event.
   // ClientHandler::OnBeforeClose will be called after the CEF NSView hosted in
   // the NSWindow is dealloc'ed.
   //
   // After the final browser window has closed ClientHandler::OnBeforeClose will
   // begin actual tear-down of the application by calling CefQuitMessageLoop.
   // This ends the NSApplication event loop and execution then returns to the
   // main() function for cleanup before application termination.
   //
   // The standard |-applicationShouldTerminate:| is not supported, and code paths
   // leading to it must be redirected.
   - (void)terminate:(id)sender {
   //  ClientAppDelegate* delegate = static_cast<ClientAppDelegate*>(
     //    [[NSApplication sharedApplication] delegate]);
    // [delegate tryToTerminateApplication:self];
     // Return, don't exit. The application is responsible for exiting on its own.
     [super terminate: sender];
   }
   
   // Detect dynamically if VoiceOver is running. Like Chromium, rely upon the
   // undocumented accessibility attribute @"AXEnhancedUserInterface" which is set
   // when VoiceOver is launched and unset when VoiceOver is closed.
   - (void)accessibilitySetValue:(id)value forAttribute:(NSString*)attribute {
    // if ([attribute isEqualToString:@"AXEnhancedUserInterface"]) {
      // ClientAppDelegate* delegate = static_cast<ClientAppDelegate*>(
       //    [[NSApplication sharedApplication] delegate]);
       //[delegate enableAccessibility:([value intValue] == 1)];
    // }
     return [super accessibilitySetValue:value forAttribute:attribute];
   }
   @end
   
   

int main(int argc, const char * argv[]) {
    // Load the CEF library. This is required for macOS.
    CefScopedLibraryLoader library_loader;
    if (!library_loader.LoadInMain())
    {
        return 1;
    }

    @autoreleasepool {
        ClientApplication *app = [ClientApplication sharedApplication];
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
        
        WindowDelegate *windowDelegate = [[WindowDelegate alloc] init];
        windowDelegate.metalView = metalView;
        [window setDelegate: windowDelegate];
        // Add the Metal view to the window
        [window.contentView addSubview:metalView];
        
        // Make the Metal view the first responder for text input
        [window makeFirstResponder:metalView];
        
        // Configure the window
        [window setTitle:@"Shrome"];
        [window center];
        [window makeKeyAndOrderFront:nil];
        
        // Set the application activation policy
        [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
           
        // Run the application
        [NSApp run];

        for(int i=0;i<10;++i) {
            CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.01, 1);
            CefDoMessageLoopWork();
            [NSThread sleepForTimeInterval:0.05];
        }

       // CefShutdown();
    }
  
    return 0;
}
