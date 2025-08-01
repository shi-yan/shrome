#import <MetalKit/MetalKit.h>

@interface MainMetalView : MTKView <NSTextInputClient, MTKViewDelegate>

@property (nonatomic, strong) NSString *inputText;
@property (nonatomic, strong) NSAttributedString *markedText;
@property (nonatomic) NSRange markedRange;
@property (nonatomic) NSRange selectedRange;

// IME positioning properties
@property (nonatomic) NSPoint textCursorPosition;
@property (nonatomic) NSPoint lastMousePosition;
@property (nonatomic) BOOL followMouse;

- (instancetype)initWithFrame:(NSRect)frame device:(id<MTLDevice>)device;

// IME positioning control methods
- (void)setCursorPosition:(NSPoint)position;
- (void)toggleMouseFollowing;
- (void)setFollowMouse:(BOOL)followMouse;

@end
