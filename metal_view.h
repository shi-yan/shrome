#import <MetalKit/MetalKit.h>

@interface AppDelegate : NSObject <NSApplicationDelegate>
{
}

@end

@interface MainMetalView : MTKView <NSTextInputClient, MTKViewDelegate>

@property(nonatomic, strong) NSString *inputText;
@property(nonatomic, strong) NSAttributedString *markedText;
@property(nonatomic) NSRange markedRange;
@property(nonatomic) NSRange selectedRange;

// IME positioning properties
@property(nonatomic) NSPoint textCursorPosition;
@property(nonatomic) NSPoint lastMousePosition;
@property(nonatomic) BOOL followMouse;

- (instancetype)initWithFrame:(NSRect)frame device:(id<MTLDevice>)device;

// IME positioning control methods
- (void)setCursorPosition:(NSPoint)position;
- (void)toggleMouseFollowing;
- (void)setFollowMouse:(BOOL)followMouse;

// Helper method for converting modifier flags
- (uint32_t)convertModifiers:(NSUInteger)appKitModifiers;

- (int)setupCEF;

@end
