#import <MetalKit/MetalKit.h>



@interface AppDelegate : NSObject <NSApplicationDelegate> {
CFRunLoopSourceRef _cefRunLoopSource;
NSTimer* _cefWorkTimer;
}

- (void)doCefMessageLoopWork;

- (void)scheduleCefMessageLoopWork:(int64_t)delay_ms;
@end





@interface MainMetalView : MTKView <NSTextInputClient, MTKViewDelegate>

@property (nonatomic, strong) NSString *inputText;
@property (nonatomic, strong) NSAttributedString *markedText;
@property (nonatomic) NSRange markedRange;
@property (nonatomic) NSRange selectedRange;

// IME positioning properties
@property (nonatomic) NSPoint textCursorPosition;
@property (nonatomic) NSPoint lastMousePosition;
@property (nonatomic) BOOL followMouse;

- (instancetype)initWithFrame:(NSRect)frame device:(id<MTLDevice>)device appDelegate:(AppDelegate *)appDelegate;

// IME positioning control methods
- (void)setCursorPosition:(NSPoint)position;
- (void)toggleMouseFollowing;
- (void)setFollowMouse:(BOOL)followMouse;

- (int) setupCEF;

@end
