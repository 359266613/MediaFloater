#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <AudioToolbox/AudioServices.h>
#import <MediaPlayer/MediaPlayer.h>
#import <MediaRemote/MediaRemote.h>
#import <AVFoundation/AVFoundation.h>
#import <QuartzCore/QuartzCore.h>

// ========== 私有音量控制 ==========
@interface AVSystemController : NSObject
+ (instancetype)sharedAVSystemController;
- (BOOL)getVolume:(float *)volume forCategory:(NSString *)category;
- (BOOL)setVolumeTo:(float)volume forCategory:(NSString *)category;
@end

// ========== 系统音效与震动 ==========
static void playClickSound(void) {
    AudioServicesPlaySystemSound(1104);
}

static void playImpactFeedback(void) {
    AudioServicesPlaySystemSound(1519);
}

// ========== Hook 的私有类（只用于数据获取） ==========
@interface SBMediaController : NSObject
+ (instancetype)sharedInstance;
- (void)setNowPlayingInfo:(NSDictionary *)info;
@end

// ========== 音量控制视图（水位直角，容器裁剪圆角，阴影可见） ==========
@interface MediaFloaterVolumeView : UIView
@property (nonatomic, assign) CGFloat currentVolume;
- (void)setLevel:(CGFloat)level animated:(BOOL)animated;
- (void)setSymbolName:(NSString *)symbolName;
- (void)setVolume:(CGFloat)volume animated:(BOOL)animated;
- (CGFloat)waterLevelY;
@end

@implementation MediaFloaterVolumeView {
    UIView *_clipContainer;
    UIView *_fillView;
    UIImageView *_iconView;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.layer.cornerRadius = 14;
        self.clipsToBounds = NO;

        self.layer.shadowColor = [UIColor blackColor].CGColor;
        self.layer.shadowOpacity = 0.6;
        self.layer.shadowOffset = CGSizeMake(0, 6);
        self.layer.shadowRadius = 10;

        _clipContainer = [[UIView alloc] initWithFrame:self.bounds];
        _clipContainer.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        _clipContainer.layer.cornerRadius = 14;
        _clipContainer.clipsToBounds = YES;
        _clipContainer.backgroundColor = [UIColor clearColor];
        [self addSubview:_clipContainer];

        UIVisualEffectView *blur = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterialDark]];
        blur.frame = _clipContainer.bounds;
        blur.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [_clipContainer addSubview:blur];

        _fillView = [[UIView alloc] initWithFrame:_clipContainer.bounds];
        _fillView.backgroundColor = [UIColor whiteColor];
        _fillView.layer.cornerRadius = 0;
        [_clipContainer addSubview:_fillView];

        _iconView = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, 24, 24)];
        _iconView.contentMode = UIViewContentModeScaleAspectFit;
        _iconView.image = [[UIImage systemImageNamed:@"speaker.wave.2.fill"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
        _iconView.tintColor = [UIColor grayColor];
        _iconView.center = CGPointMake(frame.size.width / 2, 20);
        [_clipContainer addSubview:_iconView];

        float vol = 0.5;
        AVSystemController *av = [NSClassFromString(@"AVSystemController") sharedAVSystemController];
        [av getVolume:&vol forCategory:@"Audio/Video"];
        _currentVolume = vol;
        [self updateFillHeight:vol animated:NO];
    }
    return self;
}

- (CGFloat)waterLevelY {
    CGFloat fillHeight = self.bounds.size.height * _currentVolume;
    return self.bounds.size.height - fillHeight;
}

- (void)updateFillHeight:(CGFloat)volume animated:(BOOL)animated {
    _currentVolume = MAX(0.0, MIN(1.0, volume));
    CGFloat fillHeight = self.bounds.size.height * _currentVolume;
    CGRect fillFrame = CGRectMake(0, self.bounds.size.height - fillHeight, self.bounds.size.width, fillHeight);
    if (animated) {
        [UIView animateWithDuration:0.1 animations:^{
            _fillView.frame = fillFrame;
        }];
    } else {
        _fillView.frame = fillFrame;
    }
}

- (void)setLevel:(CGFloat)level animated:(BOOL)animated {
    [self updateFillHeight:level animated:animated];
}

- (void)setSymbolName:(NSString *)symbolName {
    UIImage *image = [UIImage systemImageNamed:symbolName ?: @"speaker.wave.2.fill"];
    _iconView.image = [image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
}

- (void)setVolume:(CGFloat)volume animated:(BOOL)animated {
    AVSystemController *av = [NSClassFromString(@"AVSystemController") sharedAVSystemController];
    [av setVolumeTo:volume forCategory:@"Audio/Video"];
    [self updateFillHeight:volume animated:animated];
}

@end

// ========== 手势处理类 ==========
@interface MediaFloaterGestureHandler : NSObject <UIGestureRecognizerDelegate>
@property (nonatomic, weak) UIWindow *targetWindow;
@property (nonatomic, strong) MediaFloaterVolumeView *volumeView;
@property (nonatomic, assign) BOOL isVolumeMode;
@property (nonatomic, assign) BOOL isSpeedMode;
@property (nonatomic, assign) CGFloat initialVolume;
@property (nonatomic, assign) CGFloat initialFingerY;
@property (nonatomic, assign) CGFloat initialRotationDuration;
- (void)handleTap:(UITapGestureRecognizer *)tap;
- (void)handleDoubleTap:(UITapGestureRecognizer *)tap;
- (void)handleLongPress:(UILongPressGestureRecognizer *)longPress;
- (void)handlePan:(UIPanGestureRecognizer *)pan;
- (void)activateVolumeMode;
- (void)activateRotationSpeedMode;
- (void)deactivateVerticalControlMode;
@end

// ========== 函数前向声明 ==========
static void updateUIWithNowPlayingInfo(void);
static void updateUIWithNowPlayingInfoDictionary(NSDictionary *info, BOOL isPlaying);
static NSString *trackIdentifierFromNowPlayingInfo(NSDictionary *info);
static UIImage *coverImageFromNowPlayingInfo(NSDictionary *info);
static void applyAlbumArtImage(UIImage *cover, BOOL animated);
static void resetAlbumArtRotationState(void);
static void updateAlbumArtRotation(BOOL isPlaying);
static void scheduleArtworkRetry(void);
static CGRect constrainFrameToScreen(CGRect frame);
static void saveCurrentOrigin(void);
static void loadCurrentOrigin(void);
static void createFloatWindow(void);
static void ensureFloatWindowReady(void);
static UIWindowScene *findBestWindowScene(void);
static void scheduleFloatWindowRetry(NSTimeInterval delay);
static void registerLifecycleObservers(void);
static void registerNowPlayingObservers(void);

// ========== 悬浮窗 UI 全局变量 ==========
static UIWindow *floatWindow = nil;
static UIImageView *albumArtView = nil;
static const CGFloat kWindowSize = 55.0;
static const NSTimeInterval kArtworkRetryInterval = 0.22;
static const NSInteger kArtworkRetryMaxAttempts = 6;
static NSString * const kAlbumArtRotationAnimationKey = @"MediaFloaterAlbumArtRotation";
static NSString * const kMediaFloaterDefaultsSuiteName = @"com.axs.mediafloater";
static NSString * const kRotationDurationDefaultsKey = @"RotationDuration";
static const CGFloat kRotationDurationDefault = 4.0;
static const CGFloat kRotationDurationMin = 2.0;
static const CGFloat kRotationDurationMax = 6.0;
static CGPoint currentOrigin = {20, 100};
static CGFloat currentRotationDuration = kRotationDurationDefault;
static BOOL currentPlaybackIsPlaying = NO;

static NSString *currentTrackIdentifier = nil;
static NSInteger artworkRetryToken = 0;
static NSInteger artworkRetryAttemptsRemaining = 0;
static BOOL artworkRetryScheduled = NO;

static BOOL isLongPressActive = NO;
static BOOL hasTriggeredControl = NO;
static BOOL didMoveWindowDuringPan = NO;
static CGPoint panStartLocation;
static CGPoint panStartLocationInWindow;
static CGRect originalWindowFrame;

static BOOL wasPlayingInfoAvailable = NO;
static BOOL userSuppressedAutoShow = NO;
static BOOL floatWindowRetryScheduled = NO;

static CGFloat clampRotationDuration(CGFloat duration) {
    return MAX(kRotationDurationMin, MIN(kRotationDurationMax, duration));
}

static CGFloat rotationDurationProgress(CGFloat duration) {
    CGFloat clampedDuration = clampRotationDuration(duration);
    return (kRotationDurationMax - clampedDuration) / (kRotationDurationMax - kRotationDurationMin);
}

static CGRect constrainFrameToScreen(CGRect frame) {
    CGRect screen = [UIScreen mainScreen].bounds;
    if (frame.origin.x + kWindowSize > screen.size.width) frame.origin.x = screen.size.width - kWindowSize;
    if (frame.origin.y + kWindowSize > screen.size.height) frame.origin.y = screen.size.height - kWindowSize;
    if (frame.origin.x < 0) frame.origin.x = 0;
    if (frame.origin.y < 0) frame.origin.y = 0;
    return frame;
}

static void saveCurrentOrigin(void) {
    NSUserDefaults *def = [[NSUserDefaults alloc] initWithSuiteName:kMediaFloaterDefaultsSuiteName];
    [def setFloat:currentOrigin.x forKey:@"FloatOriginX"];
    [def setFloat:currentOrigin.y forKey:@"FloatOriginY"];
    [def synchronize];
}

static void loadCurrentOrigin(void) {
    NSUserDefaults *def = [[NSUserDefaults alloc] initWithSuiteName:kMediaFloaterDefaultsSuiteName];
    NSNumber *x = [def objectForKey:@"FloatOriginX"];
    NSNumber *y = [def objectForKey:@"FloatOriginY"];
    if (x && y) {
        currentOrigin = CGPointMake(x.floatValue, y.floatValue);
    }
    CGRect frame = CGRectMake(currentOrigin.x, currentOrigin.y, kWindowSize, kWindowSize);
    frame = constrainFrameToScreen(frame);
    currentOrigin = frame.origin;
}

static void saveRotationDuration(void) {
    NSUserDefaults *def = [[NSUserDefaults alloc] initWithSuiteName:kMediaFloaterDefaultsSuiteName];
    [def setFloat:currentRotationDuration forKey:kRotationDurationDefaultsKey];
    [def synchronize];
}

static void loadRotationDuration(void) {
    NSUserDefaults *def = [[NSUserDefaults alloc] initWithSuiteName:kMediaFloaterDefaultsSuiteName];
    id storedValue = [def objectForKey:kRotationDurationDefaultsKey];
    if (storedValue) {
        currentRotationDuration = clampRotationDuration([def floatForKey:kRotationDurationDefaultsKey]);
    } else {
        currentRotationDuration = kRotationDurationDefault;
    }
}

static NSString* safeStringFromObject(id obj) {
    if (!obj || obj == (id)[NSNull null]) return nil;
    if ([obj isKindOfClass:[NSString class]]) return obj;
    return nil;
}

// ========== 改进的封面裁剪函数（以短边为准，居中裁剪，无变形） ==========
static UIImage *circleImageWithSize(UIImage *image, CGFloat size) {
    if (!image) return nil;
    
    // 计算缩放比例：以短边为准填满画布
    CGFloat scale = MAX(size / image.size.width, size / image.size.height);
    CGFloat scaledWidth = image.size.width * scale;
    CGFloat scaledHeight = image.size.height * scale;
    
    // 居中绘制矩形
    CGRect drawRect = CGRectMake((size - scaledWidth) / 2,
                                 (size - scaledHeight) / 2,
                                 scaledWidth,
                                 scaledHeight);
    
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(size, size)];
    UIImage *output = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        // 先裁剪为圆形
        UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, size, size) cornerRadius:size/2];
        [path addClip];
        // 绘制图片（保持比例，居中裁剪）
        [image drawInRect:drawRect];
    }];
    return output;
}

static UIWindowScene *findBestWindowScene(void) {
    UIApplication *application = [UIApplication sharedApplication];
    UIWindowScene *fallbackScene = nil;

    for (UIScene *scene in application.connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) continue;
        UIWindowScene *windowScene = (UIWindowScene *)scene;
        if (!fallbackScene) fallbackScene = windowScene;
        if (scene.activationState == UISceneActivationStateForegroundActive) {
            return windowScene;
        }
    }

    for (UIScene *scene in application.connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) continue;
        if (scene.activationState == UISceneActivationStateForegroundInactive) {
            return (UIWindowScene *)scene;
        }
    }

    return fallbackScene;
}

static void scheduleFloatWindowRetry(NSTimeInterval delay) {
    if (floatWindow || floatWindowRetryScheduled) return;
    floatWindowRetryScheduled = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        floatWindowRetryScheduled = NO;
        ensureFloatWindowReady();
    });
}

static void ensureFloatWindowReady(void) {
    if (floatWindow && albumArtView && floatWindow.windowScene) return;

    if (floatWindow && (!albumArtView || !floatWindow.windowScene)) {
        [albumArtView removeFromSuperview];
        albumArtView = nil;
        floatWindow.hidden = YES;
        floatWindow.rootViewController = nil;
        floatWindow = nil;
    }

    createFloatWindow();
    if (!floatWindow) {
        scheduleFloatWindowRetry(0.8);
    }
}

static NSString *trackIdentifierFromNowPlayingInfo(NSDictionary *info) {
    if (![info isKindOfClass:[NSDictionary class]]) return nil;

    id persistentID = info[MPMediaItemPropertyPersistentID] ?: info[@"kMRMediaRemoteNowPlayingInfoUniqueIdentifier"];
    if (persistentID && persistentID != (id)[NSNull null]) {
        return [persistentID description];
    }

    NSString *title = safeStringFromObject(info[MPMediaItemPropertyTitle] ?: info[(__bridge NSString *)kMRMediaRemoteNowPlayingInfoTitle] ?: info[@"kMRMediaRemoteNowPlayingInfoTitle"]);
    NSString *artist = safeStringFromObject(info[MPMediaItemPropertyArtist] ?: info[(__bridge NSString *)kMRMediaRemoteNowPlayingInfoArtist] ?: info[@"kMRMediaRemoteNowPlayingInfoArtist"]);
    NSString *album = safeStringFromObject(info[MPMediaItemPropertyAlbumTitle] ?: info[(__bridge NSString *)kMRMediaRemoteNowPlayingInfoAlbum] ?: info[@"kMRMediaRemoteNowPlayingInfoAlbum"]);
    NSNumber *duration = info[MPMediaItemPropertyPlaybackDuration] ?: info[(__bridge NSString *)kMRMediaRemoteNowPlayingInfoDuration] ?: info[@"kMRMediaRemoteNowPlayingInfoDuration"];

    NSMutableArray *parts = [NSMutableArray array];
    if (title.length) [parts addObject:title];
    if (artist.length) [parts addObject:artist];
    if (album.length) [parts addObject:album];
    if ([duration respondsToSelector:@selector(stringValue)]) {
        [parts addObject:[duration stringValue]];
    }

    return parts.count ? [parts componentsJoinedByString:@"|"] : nil;
}

static UIImage *coverImageFromNowPlayingInfo(NSDictionary *info) {
    if (![info isKindOfClass:[NSDictionary class]]) return nil;

    NSData *artworkData = info[(__bridge NSString *)kMRMediaRemoteNowPlayingInfoArtworkData] ?: info[@"kMRMediaRemoteNowPlayingInfoArtworkData"];
    if ([artworkData isKindOfClass:[NSData class]] && artworkData.length > 0) {
        UIImage *rawImage = [UIImage imageWithData:artworkData];
        if (rawImage) {
            return circleImageWithSize(rawImage, kWindowSize);
        }
    }

    id artworkObject = info[MPMediaItemPropertyArtwork];
    if ([artworkObject isKindOfClass:[MPMediaItemArtwork class]]) {
        UIImage *rawArtwork = nil;
        if (@available(iOS 10.0, *)) {
            rawArtwork = [(MPMediaItemArtwork *)artworkObject imageWithSize:CGSizeMake(kWindowSize * 2, kWindowSize * 2)];
        }
        if (rawArtwork) {
            return circleImageWithSize(rawArtwork, kWindowSize);
        }
    }

    return nil;
}

static void applyAlbumArtImage(UIImage *cover, BOOL animated) {
    if (!albumArtView) return;

    void (^changes)(void) = ^{
        albumArtView.image = cover;
        albumArtView.backgroundColor = cover ? [UIColor clearColor] : [UIColor blackColor];
    };

    if (animated && (albumArtView.image || cover)) {
        [UIView transitionWithView:albumArtView
                          duration:0.08
                           options:UIViewAnimationOptionTransitionCrossDissolve | UIViewAnimationOptionBeginFromCurrentState
                        animations:changes
                        completion:nil];
    } else {
        changes();
    }
}

static void resetAlbumArtRotationState(void) {
    if (!albumArtView) return;

    CALayer *layer = albumArtView.layer;
    [layer removeAnimationForKey:kAlbumArtRotationAnimationKey];
    layer.speed = 1.0;
    layer.timeOffset = 0.0;
    layer.beginTime = 0.0;
}

static void updateAlbumArtRotation(BOOL isPlaying) {
    if (!albumArtView) return;

    CALayer *layer = albumArtView.layer;
    CGFloat speedFactor = kRotationDurationDefault / currentRotationDuration;
    if (![layer animationForKey:kAlbumArtRotationAnimationKey]) {
        layer.speed = speedFactor;
        layer.timeOffset = 0.0;
        layer.beginTime = 0.0;

        CABasicAnimation *rotation = [CABasicAnimation animationWithKeyPath:@"transform.rotation.z"];
        rotation.fromValue = @(0.0);
        rotation.toValue = @(M_PI * 2.0);
        rotation.duration = kRotationDurationDefault;
        rotation.repeatCount = HUGE_VALF;
        rotation.removedOnCompletion = NO;
        rotation.fillMode = kCAFillModeForwards;
        [layer addAnimation:rotation forKey:kAlbumArtRotationAnimationKey];
    }

    if (isPlaying) {
        if (layer.speed == 0.0) {
            CFTimeInterval pausedTime = layer.timeOffset;
            layer.speed = speedFactor;
            layer.timeOffset = 0.0;
            layer.beginTime = 0.0;
            CFTimeInterval timeSincePause = [layer convertTime:CACurrentMediaTime() fromLayer:nil] - pausedTime;
            layer.beginTime = timeSincePause;
        } else {
            layer.speed = speedFactor;
        }
    } else if (layer.speed != 0.0) {
        CFTimeInterval pausedTime = [layer convertTime:CACurrentMediaTime() fromLayer:nil];
        layer.speed = 0.0;
        layer.timeOffset = pausedTime;
    }
}

static void scheduleArtworkRetry(void) {
    if (artworkRetryScheduled || artworkRetryAttemptsRemaining <= 0) return;

    NSInteger retryToken = artworkRetryToken;
    artworkRetryScheduled = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kArtworkRetryInterval * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        artworkRetryScheduled = NO;
        if (retryToken != artworkRetryToken || artworkRetryAttemptsRemaining <= 0) return;

        artworkRetryAttemptsRemaining -= 1;
        updateUIWithNowPlayingInfo();
    });
}

static void updateUIWithNowPlayingInfoDictionary(NSDictionary *info, BOOL isPlaying) {
    ensureFloatWindowReady();
    if (!albumArtView || !floatWindow) return;

    currentPlaybackIsPlaying = isPlaying;

    BOOL hasInfo = [info isKindOfClass:[NSDictionary class]] && info.count > 0;
    if (!hasInfo) {
        artworkRetryToken += 1;
        artworkRetryAttemptsRemaining = 0;
        artworkRetryScheduled = NO;
        currentTrackIdentifier = nil;

        if (wasPlayingInfoAvailable) {
            floatWindow.hidden = YES;
            wasPlayingInfoAvailable = NO;
        }

        applyAlbumArtImage(nil, NO);
        albumArtView.layer.borderWidth = 0;
        updateAlbumArtRotation(NO);
        userSuppressedAutoShow = NO;
        return;
    }

    NSString *newTrackIdentifier = trackIdentifierFromNowPlayingInfo(info);
    BOOL trackChanged = ![(newTrackIdentifier ?: @"") isEqualToString:(currentTrackIdentifier ?: @"")];
    if (trackChanged) {
        currentTrackIdentifier = [newTrackIdentifier copy];
        artworkRetryToken += 1;
        artworkRetryAttemptsRemaining = kArtworkRetryMaxAttempts;
        artworkRetryScheduled = NO;
    }

    UIImage *cover = coverImageFromNowPlayingInfo(info);

    if (cover) {
        if (artworkRetryAttemptsRemaining > 0 || artworkRetryScheduled) {
            artworkRetryToken += 1;
        }
        artworkRetryAttemptsRemaining = 0;
        artworkRetryScheduled = NO;
    }

    if (!wasPlayingInfoAvailable && !userSuppressedAutoShow) {
        floatWindow.hidden = NO;
        wasPlayingInfoAvailable = YES;
    }

    if (cover) {
        if (trackChanged) {
            resetAlbumArtRotationState();
        }
        applyAlbumArtImage(cover, trackChanged || !albumArtView.image);
    } else if (!albumArtView.image) {
        applyAlbumArtImage(nil, NO);
    }

    albumArtView.layer.borderWidth = isPlaying ? 2.0 : 0.0;
    albumArtView.layer.borderColor = [UIColor systemGreenColor].CGColor;
    updateAlbumArtRotation(isPlaying);

    if (!cover && artworkRetryAttemptsRemaining > 0) {
        scheduleArtworkRetry();
    }
}

static void updateUIWithNowPlayingInfo(void) {
    ensureFloatWindowReady();
    if (!albumArtView || !floatWindow) return;

    MRMediaRemoteGetNowPlayingInfo(dispatch_get_main_queue(), ^(CFDictionaryRef information) {
        NSDictionary *info = information ? (__bridge NSDictionary *)information : nil;
        MRMediaRemoteGetNowPlayingApplicationIsPlaying(dispatch_get_main_queue(), ^(Boolean isPlayingNow) {
            updateUIWithNowPlayingInfoDictionary(info, (BOOL)isPlayingNow);
        });
    });
}

%hook SBMediaController
- (void)setNowPlayingInfo:(NSDictionary *)info {
    %orig;
    dispatch_async(dispatch_get_main_queue(), ^{
        updateUIWithNowPlayingInfo();
    });
}
%end

// ========== 手势处理类实现 ==========
@implementation MediaFloaterGestureHandler

- (void)handleTap:(UITapGestureRecognizer *)tap {
    if (self.isVolumeMode || self.isSpeedMode) return;
    playClickSound();
    MRMediaRemoteSendCommand(MRMediaRemoteCommandTogglePlayPause, nil);
}

- (void)handleDoubleTap:(UITapGestureRecognizer *)tap {
    if (self.isVolumeMode || self.isSpeedMode) return;
    floatWindow.hidden = YES;
    wasPlayingInfoAvailable = NO;
    userSuppressedAutoShow = YES;
    playImpactFeedback();
}

- (void)handleLongPress:(UILongPressGestureRecognizer *)longPress {
    if (self.isVolumeMode || self.isSpeedMode) return;

    UIWindow *window = self.targetWindow;
    if (!window) window = longPress.view.window;
    if (!window) return;

    if (longPress.state == UIGestureRecognizerStateBegan) {
        playImpactFeedback();
        isLongPressActive = YES;
        didMoveWindowDuringPan = NO;
        panStartLocationInWindow = [longPress locationInView:window];
        return;
    }

    if (longPress.state == UIGestureRecognizerStateChanged) {
        if (!isLongPressActive) return;

        CGPoint screenLocation = [longPress locationInView:nil];
        CGRect newFrame = window.frame;
        newFrame.origin.x = screenLocation.x - panStartLocationInWindow.x;
        newFrame.origin.y = screenLocation.y - panStartLocationInWindow.y;
        newFrame = constrainFrameToScreen(newFrame);
        window.frame = newFrame;
        didMoveWindowDuringPan = YES;
        return;
    }

    if (longPress.state == UIGestureRecognizerStateEnded || longPress.state == UIGestureRecognizerStateCancelled) {
        if (didMoveWindowDuringPan) {
            CGRect newFrame = constrainFrameToScreen(window.frame);
            window.frame = newFrame;
            currentOrigin = newFrame.origin;
            saveCurrentOrigin();
        }

        isLongPressActive = NO;
        didMoveWindowDuringPan = NO;
    }
}

- (void)handlePan:(UIPanGestureRecognizer *)pan {
    UIWindow *window = self.targetWindow;
    if (!window) window = pan.view.window;
    if (!window) return;

    CGPoint currentLocation = [pan locationInView:nil];

    if (pan.state == UIGestureRecognizerStateBegan) {
        originalWindowFrame = window.frame;
        hasTriggeredControl = NO;
        didMoveWindowDuringPan = NO;
        panStartLocation = currentLocation;
        panStartLocationInWindow = [pan locationInView:window];
        return;
    }

    CGFloat deltaX = currentLocation.x - panStartLocation.x;
    CGFloat deltaY = currentLocation.y - panStartLocation.y;

    if (pan.state == UIGestureRecognizerStateChanged) {
        if (self.isVolumeMode && self.volumeView) {
            CGFloat fingerDeltaY = currentLocation.y - self.initialFingerY;
            CGFloat newVol = self.initialVolume - (fingerDeltaY / 200.0);
            newVol = MAX(0.0, MIN(1.0, newVol));
            [self.volumeView setVolume:newVol animated:YES];
            return;
        }

        if (self.isSpeedMode && self.volumeView) {
            CGFloat fingerDeltaY = currentLocation.y - self.initialFingerY;
            CGFloat newDuration = self.initialRotationDuration + (fingerDeltaY / 20.0);
            currentRotationDuration = clampRotationDuration(newDuration);
            [self.volumeView setLevel:rotationDurationProgress(currentRotationDuration) animated:YES];
            return;
        }

        if (!hasTriggeredControl) {
            CGFloat absDeltaX = fabs(deltaX);
            CGFloat absDeltaY = fabs(deltaY);

            if (absDeltaY > absDeltaX && absDeltaY > 24.0) {
                hasTriggeredControl = YES;
                playImpactFeedback();
                if (deltaY < 0) {
                    [self activateVolumeMode];
                    CGFloat fingerDeltaY = currentLocation.y - self.initialFingerY;
                    CGFloat newVol = self.initialVolume - (fingerDeltaY / 200.0);
                    newVol = MAX(0.0, MIN(1.0, newVol));
                    [self.volumeView setVolume:newVol animated:NO];
                } else {
                    [self activateRotationSpeedMode];
                    CGFloat fingerDeltaY = currentLocation.y - self.initialFingerY;
                    CGFloat newDuration = self.initialRotationDuration + (fingerDeltaY / 20.0);
                    currentRotationDuration = clampRotationDuration(newDuration);
                    [self.volumeView setLevel:rotationDurationProgress(currentRotationDuration) animated:NO];
                }
                return;
            }

            if (absDeltaX > absDeltaY && absDeltaX > 30.0) {
                hasTriggeredControl = YES;
                playImpactFeedback();
                if (deltaX > 0) {
                    MRMediaRemoteSendCommand(MRMediaRemoteCommandNextTrack, nil);
                } else {
                    MRMediaRemoteSendCommand(MRMediaRemoteCommandPreviousTrack, nil);
                }
                return;
            }
        }
    } else if (pan.state == UIGestureRecognizerStateEnded || pan.state == UIGestureRecognizerStateCancelled) {
        BOOL didFinishMove = didMoveWindowDuringPan || isLongPressActive;

        if (self.isVolumeMode || self.isSpeedMode) {
            if (self.isSpeedMode) {
                saveRotationDuration();
            }
            [self deactivateVerticalControlMode];
            [UIView animateWithDuration:0.25 animations:^{
                window.frame = CGRectMake(currentOrigin.x, currentOrigin.y, kWindowSize, kWindowSize);
            }];
            hasTriggeredControl = NO;
            didMoveWindowDuringPan = NO;
            return;
        }

        if (didFinishMove) {
            CGRect newFrame = constrainFrameToScreen(window.frame);
            window.frame = newFrame;
            currentOrigin = newFrame.origin;
            saveCurrentOrigin();
        } else {
            CGRect targetFrame = constrainFrameToScreen(CGRectMake(currentOrigin.x, currentOrigin.y, kWindowSize, kWindowSize));
            currentOrigin = targetFrame.origin;
            [UIView animateWithDuration:0.25 animations:^{
                window.frame = targetFrame;
            }];
        }

        isLongPressActive = NO;
        hasTriggeredControl = NO;
        didMoveWindowDuringPan = NO;
    }
}

- (void)activateVolumeMode {
    if (self.isVolumeMode || self.isSpeedMode) return;
    self.isVolumeMode = YES;

    UIWindow *window = self.targetWindow;
    if (!window) return;

    UIView *contentView = window.rootViewController.view ?: window;
    CGRect volumeFrame = CGRectMake(0, 0, kWindowSize, 150);
    self.volumeView = [[MediaFloaterVolumeView alloc] initWithFrame:volumeFrame];
    self.volumeView.alpha = 0;
    self.volumeView.transform = CGAffineTransformMakeScale(0.8, 0.8);
    [self.volumeView setSymbolName:@"speaker.wave.2.fill"];
    [contentView addSubview:self.volumeView];

    self.volumeView.center = panStartLocationInWindow;

    float sysVol = 0.5;
    AVSystemController *av = [NSClassFromString(@"AVSystemController") sharedAVSystemController];
    [av getVolume:&sysVol forCategory:@"Audio/Video"];
    [self.volumeView setVolume:sysVol animated:NO];
    self.initialVolume = sysVol;
    self.initialFingerY = panStartLocation.y;

    [UIView animateWithDuration:0.25 animations:^{
        self.volumeView.alpha = 1;
        self.volumeView.transform = CGAffineTransformIdentity;
    }];
}

- (void)activateRotationSpeedMode {
    if (self.isVolumeMode || self.isSpeedMode) return;
    self.isSpeedMode = YES;

    UIWindow *window = self.targetWindow;
    if (!window) return;

    UIView *contentView = window.rootViewController.view ?: window;
    CGRect controlFrame = CGRectMake(0, 0, kWindowSize, 150);
    self.volumeView = [[MediaFloaterVolumeView alloc] initWithFrame:controlFrame];
    self.volumeView.alpha = 0;
    self.volumeView.transform = CGAffineTransformMakeScale(0.8, 0.8);
    [self.volumeView setSymbolName:@"dial.medium.fill"];
    [self.volumeView setLevel:rotationDurationProgress(currentRotationDuration) animated:NO];
    [contentView addSubview:self.volumeView];

    self.volumeView.center = panStartLocationInWindow;
    self.initialFingerY = panStartLocation.y;
    self.initialRotationDuration = currentRotationDuration;

    [UIView animateWithDuration:0.25 animations:^{
        self.volumeView.alpha = 1;
        self.volumeView.transform = CGAffineTransformIdentity;
    }];
}

- (void)deactivateVerticalControlMode {
    if (!self.isVolumeMode && !self.isSpeedMode) return;
    self.isVolumeMode = NO;
    self.isSpeedMode = NO;

    [UIView animateWithDuration:0.25 animations:^{
        self.volumeView.alpha = 0;
        self.volumeView.transform = CGAffineTransformMakeScale(0.8, 0.8);
    } completion:^(BOOL finished) {
        [self.volumeView removeFromSuperview];
        self.volumeView = nil;
    }];
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer {
    if ([gestureRecognizer isKindOfClass:[UITapGestureRecognizer class]]) {
        return !isLongPressActive && !self.isVolumeMode && !self.isSpeedMode;
    }
    return YES;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    return NO;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRequireFailureOfGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    if ([gestureRecognizer isKindOfClass:[UITapGestureRecognizer class]]) {
        if ([otherGestureRecognizer isKindOfClass:[UIPanGestureRecognizer class]] || [otherGestureRecognizer isKindOfClass:[UILongPressGestureRecognizer class]]) {
            return YES;
        }
    }
    return NO;
}

@end

// ========== 创建悬浮窗（增加阴影） ==========
static void createFloatWindow(void) {
    if (floatWindow) return;

    UIWindowScene *scene = findBestWindowScene();
    if (!scene) return;

    loadCurrentOrigin();

    floatWindow = [[UIWindow alloc] initWithWindowScene:scene];
    floatWindow.frame = CGRectMake(currentOrigin.x, currentOrigin.y, kWindowSize, kWindowSize);
    floatWindow.windowLevel = UIWindowLevelStatusBar + 100;
    floatWindow.backgroundColor = [UIColor clearColor];
    floatWindow.userInteractionEnabled = YES;
    floatWindow.hidden = YES;
    floatWindow.clipsToBounds = NO;

    UIViewController *rootVC = [[UIViewController alloc] init];
    rootVC.view.frame = floatWindow.bounds;
    rootVC.view.backgroundColor = [UIColor clearColor];
    rootVC.view.userInteractionEnabled = YES;
    floatWindow.rootViewController = rootVC;

    albumArtView = [[UIImageView alloc] initWithFrame:rootVC.view.bounds];
    albumArtView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    albumArtView.contentMode = UIViewContentModeScaleAspectFill;
    albumArtView.layer.cornerRadius = kWindowSize / 2;
    albumArtView.clipsToBounds = YES;
    albumArtView.backgroundColor = [UIColor blackColor];
    albumArtView.image = nil;
    albumArtView.userInteractionEnabled = YES;

    floatWindow.layer.shadowColor = [UIColor blackColor].CGColor;
    floatWindow.layer.shadowOpacity = 0.5;
    floatWindow.layer.shadowOffset = CGSizeMake(0, 4);
    floatWindow.layer.shadowRadius = 8;
    floatWindow.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:floatWindow.bounds cornerRadius:kWindowSize / 2].CGPath;

    [rootVC.view addSubview:albumArtView];
    [floatWindow setHidden:NO];
    [floatWindow setHidden:YES];

    MediaFloaterGestureHandler *handler = [[MediaFloaterGestureHandler alloc] init];
    handler.targetWindow = floatWindow;
    objc_setAssociatedObject(albumArtView, "gestureHandler", handler, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:handler action:@selector(handleTap:)];
    UITapGestureRecognizer *doubleTap = [[UITapGestureRecognizer alloc] initWithTarget:handler action:@selector(handleDoubleTap:)];
    doubleTap.numberOfTapsRequired = 2;
    [tap requireGestureRecognizerToFail:doubleTap];
    [albumArtView addGestureRecognizer:tap];
    [albumArtView addGestureRecognizer:doubleTap];

    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:handler action:@selector(handlePan:)];
    [albumArtView addGestureRecognizer:pan];

    UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:handler action:@selector(handleLongPress:)];
    longPress.minimumPressDuration = 0.3;
    [albumArtView addGestureRecognizer:longPress];

    pan.delegate = handler;
    longPress.delegate = handler;
    tap.delegate = handler;
    doubleTap.delegate = handler;
}

static void registerLifecycleObservers(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSNotificationCenter *center = [NSNotificationCenter defaultCenter];

        void (^rebuildBlock)(NSNotification *) = ^(NSNotification *note) {
            dispatch_async(dispatch_get_main_queue(), ^{
                ensureFloatWindowReady();
                updateUIWithNowPlayingInfo();
            });
        };

        [center addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:rebuildBlock];

        if (@available(iOS 13.0, *)) {
            [center addObserverForName:UISceneDidActivateNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:rebuildBlock];
            [center addObserverForName:UISceneWillEnterForegroundNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:rebuildBlock];
        }
    });
}

static void registerNowPlayingObservers(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        MRMediaRemoteRegisterForNowPlayingNotifications(dispatch_get_main_queue());

        NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
        void (^refreshBlock)(NSNotification *) = ^(NSNotification *note) {
            dispatch_async(dispatch_get_main_queue(), ^{
                updateUIWithNowPlayingInfo();
            });
        };

        [center addObserverForName:(__bridge NSString *)kMRMediaRemoteNowPlayingInfoDidChangeNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:refreshBlock];
        [center addObserverForName:(__bridge NSString *)kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:refreshBlock];
    });
}

%ctor {
    loadRotationDuration();
    registerLifecycleObservers();
    registerNowPlayingObservers();
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        ensureFloatWindowReady();
        updateUIWithNowPlayingInfo();
    });
}