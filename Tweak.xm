#import <UIKit/UIKit.h>
#import <sys/stat.h>
#import <sys/time.h>
#import <stdarg.h>
#import <objc/runtime.h>
#import <AudioToolbox/AudioServices.h>
#import <MediaPlayer/MediaPlayer.h>
#import <MediaRemote/MediaRemote.h>
#import <AVFoundation/AVFoundation.h>

// ========== 私有音量控制 ==========
@interface AVSystemController : NSObject
+ (instancetype)sharedAVSystemController;
- (BOOL)getVolume:(float *)volume forCategory:(NSString *)category;
- (BOOL)setVolumeTo:(float)volume forCategory:(NSString *)category;
@end

// ========== 安全日志写入文件 ==========
#define LOG_FILE_PATH "/var/jb/var/mobile/MediaFloater/debug.log"

static void ensure_log_dir(void) {
    char path[256];
    strlcpy(path, LOG_FILE_PATH, sizeof(path));
    char *last_slash = strrchr(path, '/');
    if (last_slash) {
        *last_slash = '\0';
        mkdir(path, 0755);
    }
}

static void safe_log(const char *format, ...) {
    ensure_log_dir();
    FILE *fp = fopen(LOG_FILE_PATH, "a");
    if (!fp) return;
    struct timeval tv;
    gettimeofday(&tv, NULL);
    struct tm *tm = localtime(&tv.tv_sec);
    char timebuf[64];
    strftime(timebuf, sizeof(timebuf), "%Y-%m-%d %H:%M:%S", tm);
    fprintf(fp, "[%s.%03d] ", timebuf, (int)(tv.tv_usec / 1000));
    va_list args;
    va_start(args, format);
    vfprintf(fp, format, args);
    va_end(args);
    fprintf(fp, "\n");
    fclose(fp);
}

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
@property (nonatomic, assign) CGFloat initialVolume;
@property (nonatomic, assign) CGFloat initialFingerY;
- (void)handleTap:(UITapGestureRecognizer *)tap;
- (void)handleLongPress:(UILongPressGestureRecognizer *)longPress;
- (void)handlePan:(UIPanGestureRecognizer *)pan;
@end

// ========== 函数前向声明 ==========
static void updateUIWithNowPlayingInfo(void);
static CGRect constrainFrameToScreen(CGRect frame);
static void saveCurrentOrigin(void);
static void loadCurrentOrigin(void);
static void createFloatWindow(void);
static void ensureFloatWindowReady(void);
static UIWindowScene *findBestWindowScene(void);
static void scheduleFloatWindowRetry(NSTimeInterval delay);
static void registerLifecycleObservers(void);

// ========== 悬浮窗 UI 全局变量 ==========
static UIWindow *floatWindow = nil;
static UIImageView *albumArtView = nil;
static const CGFloat kWindowSize = 55.0;
static CGPoint currentOrigin = {20, 100};

static dispatch_source_t debounceTimer = nil;
static NSString *currentTitle = nil;
static NSString *currentArtist = nil;

static BOOL isLongPressActive = NO;
static BOOL hasTriggeredControl = NO;
static BOOL shouldHideOnSwipeUp = NO;
static BOOL didMoveWindowDuringPan = NO;
static CGPoint panStartLocation;
static CGPoint panStartLocationInWindow;
static CGRect originalWindowFrame;

static BOOL wasPlayingInfoAvailable = NO;
static BOOL userSuppressedAutoShow = NO;
static BOOL floatWindowRetryScheduled = NO;

static CGRect constrainFrameToScreen(CGRect frame) {
    CGRect screen = [UIScreen mainScreen].bounds;
    if (frame.origin.x + kWindowSize > screen.size.width) frame.origin.x = screen.size.width - kWindowSize;
    if (frame.origin.y + kWindowSize > screen.size.height) frame.origin.y = screen.size.height - kWindowSize;
    if (frame.origin.x < 0) frame.origin.x = 0;
    if (frame.origin.y < 0) frame.origin.y = 0;
    return frame;
}

static void saveCurrentOrigin(void) {
    NSUserDefaults *def = [[NSUserDefaults alloc] initWithSuiteName:@"com.jiuyue.mediafloater"];
    [def setFloat:currentOrigin.x forKey:@"FloatOriginX"];
    [def setFloat:currentOrigin.y forKey:@"FloatOriginY"];
    [def synchronize];
}

static void loadCurrentOrigin(void) {
    NSUserDefaults *def = [[NSUserDefaults alloc] initWithSuiteName:@"com.jiuyue.mediafloater"];
    NSNumber *x = [def objectForKey:@"FloatOriginX"];
    NSNumber *y = [def objectForKey:@"FloatOriginY"];
    if (x && y) {
        currentOrigin = CGPointMake(x.floatValue, y.floatValue);
    }
    CGRect frame = CGRectMake(currentOrigin.x, currentOrigin.y, kWindowSize, kWindowSize);
    frame = constrainFrameToScreen(frame);
    currentOrigin = frame.origin;
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
        safe_log("[MusicWidget] 检测到悬浮窗状态失效，准备重建");
        [albumArtView removeFromSuperview];
        albumArtView = nil;
        floatWindow.hidden = YES;
        floatWindow.rootViewController = nil;
        floatWindow = nil;
    }

    createFloatWindow();
    if (!floatWindow) {
        safe_log("[MusicWidget] 当前未找到可用 scene，稍后重试创建悬浮窗");
        scheduleFloatWindowRetry(0.8);
    }
}

static void updateUIWithNowPlayingInfo(void) {
    ensureFloatWindowReady();
    if (!albumArtView || !floatWindow) return;
    MRMediaRemoteGetNowPlayingInfo(dispatch_get_main_queue(), ^(CFDictionaryRef information) {
        BOOL hasInfo = (information != NULL);
        if (!hasInfo) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (wasPlayingInfoAvailable) {
                    floatWindow.hidden = YES;
                    wasPlayingInfoAvailable = NO;
                }
                albumArtView.image = nil;
                albumArtView.backgroundColor = [UIColor blackColor];
                albumArtView.layer.borderWidth = 0;
                userSuppressedAutoShow = NO;
            });
            safe_log("[MusicWidget] 无播放信息，窗口已隐藏");
            return;
        }

        NSDictionary *info = (__bridge NSDictionary *)information;
        id titleObj = info[MPMediaItemPropertyTitle] ?: info[@"kMRMediaRemoteNowPlayingInfoTitle"];
        id artistObj = info[MPMediaItemPropertyArtist] ?: info[@"kMRMediaRemoteNowPlayingInfoArtist"];
        NSString *title = safeStringFromObject(titleObj);
        NSString *artist = safeStringFromObject(artistObj);
        NSNumber *playbackRate = info[MPNowPlayingInfoPropertyPlaybackRate] ?: info[@"kMRMediaRemoteNowPlayingInfoPlaybackRate"];
        BOOL isPlaying = [playbackRate floatValue] > 0;

        BOOL songChanged = NO;
        if (title.length && artist.length) {
            if (![title isEqualToString:currentTitle] || ![artist isEqualToString:currentArtist]) {
                songChanged = YES;
                currentTitle = [title copy];
                currentArtist = [artist copy];
                safe_log("[MusicWidget] 检测到切歌: %s - %s", title.UTF8String, artist.UTF8String);
            }
        } else {
            currentTitle = nil;
            currentArtist = nil;
        }

        if (songChanged || !albumArtView.image) {
            NSDictionary *capturedInfo = info;
            int64_t delayNano = (int64_t)((songChanged ? 0.5 : 0.0) * NSEC_PER_SEC);
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, delayNano), dispatch_get_main_queue(), ^{
                NSData *artworkData = capturedInfo[@"kMRMediaRemoteNowPlayingInfoArtworkData"];
                UIImage *cover = nil;
                if ([artworkData isKindOfClass:[NSData class]] && artworkData.length > 0) {
                    UIImage *rawImage = [UIImage imageWithData:artworkData];
                    if (rawImage) {
                        cover = circleImageWithSize(rawImage, kWindowSize);
                    }
                    if (cover) safe_log("[MusicWidget] 封面获取成功");
                }
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (wasPlayingInfoAvailable) {
                        [UIView transitionWithView:albumArtView
                                          duration:0.2
                                           options:UIViewAnimationOptionTransitionCrossDissolve
                                        animations:^{
                            if (cover) {
                                albumArtView.image = cover;
                                albumArtView.backgroundColor = [UIColor clearColor];
                            } else {
                                albumArtView.image = nil;
                                albumArtView.backgroundColor = [UIColor blackColor];
                            }
                        } completion:nil];
                    }
                });
            });
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            if (!hasInfo) {
                if (wasPlayingInfoAvailable) {
                    floatWindow.hidden = YES;
                    wasPlayingInfoAvailable = NO;
                }
                userSuppressedAutoShow = NO;
            } else {
                if (!wasPlayingInfoAvailable && !userSuppressedAutoShow) {
                    floatWindow.hidden = NO;
                    wasPlayingInfoAvailable = YES;
                }
            }
            if (!albumArtView.image) {
                albumArtView.backgroundColor = [UIColor blackColor];
            }
            albumArtView.layer.borderWidth = isPlaying ? 2 : 0;
            albumArtView.layer.borderColor = [UIColor systemGreenColor].CGColor;
        });
        safe_log("[MusicWidget] 歌名: %s, 歌手: %s, 播放中: %d, 窗口可见: %d",
                 title.UTF8String ?: "", artist.UTF8String ?: "", isPlaying, !floatWindow.hidden);
    });
}

%hook SBMediaController
- (void)setNowPlayingInfo:(NSDictionary *)info {
    %orig;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (debounceTimer) dispatch_source_cancel(debounceTimer);
        debounceTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
        dispatch_source_set_timer(debounceTimer, dispatch_time(DISPATCH_TIME_NOW, 0.1 * NSEC_PER_SEC), DISPATCH_TIME_FOREVER, 0);
        dispatch_source_set_event_handler(debounceTimer, ^{
            updateUIWithNowPlayingInfo();
            dispatch_source_cancel(debounceTimer);
            debounceTimer = nil;
        });
        dispatch_resume(debounceTimer);
    });
}
%end

// ========== 手势处理类实现 ==========
@implementation MediaFloaterGestureHandler

- (void)handleTap:(UITapGestureRecognizer *)tap {
    if (self.isVolumeMode) return;
    playClickSound();
    MRMediaRemoteSendCommand(MRMediaRemoteCommandTogglePlayPause, nil);
    safe_log("[MusicWidget] 单击：播放/暂停");
}

- (void)handleLongPress:(UILongPressGestureRecognizer *)longPress {
    if (self.isVolumeMode) return;
    if (longPress.state == UIGestureRecognizerStateBegan) {
        playImpactFeedback();
        isLongPressActive = YES;
        safe_log("[MusicWidget] 长按0.3秒触发，激活纯移动模式");
    } else if (longPress.state == UIGestureRecognizerStateEnded || longPress.state == UIGestureRecognizerStateCancelled) {
        isLongPressActive = NO;
    }
}

- (void)handlePan:(UIPanGestureRecognizer *)pan {
    UIWindow *window = self.targetWindow;
    if (!window) window = pan.view.window;
    if (!window) return;

    CGPoint currentLocation = [pan locationInView:nil];
    CGFloat deltaX = currentLocation.x - panStartLocation.x;
    CGFloat deltaY = currentLocation.y - panStartLocation.y;

    if (pan.state == UIGestureRecognizerStateBegan) {
        originalWindowFrame = window.frame;
        hasTriggeredControl = NO;
        shouldHideOnSwipeUp = NO;
        didMoveWindowDuringPan = NO;
        panStartLocation = currentLocation;
        panStartLocationInWindow = [pan locationInView:window];
        return;
    }

    if (pan.state == UIGestureRecognizerStateChanged) {
        if (self.isVolumeMode && self.volumeView) {
            CGFloat fingerDeltaY = currentLocation.y - self.initialFingerY;
            CGFloat newVol = self.initialVolume - (fingerDeltaY / 200.0);
            newVol = MAX(0.0, MIN(1.0, newVol));
            [self.volumeView setVolume:newVol animated:YES];
            return;
        }

        if (isLongPressActive) {
            CGRect newFrame = originalWindowFrame;
            newFrame.origin.x += deltaX;
            newFrame.origin.y += deltaY;
            window.frame = newFrame;
            didMoveWindowDuringPan = YES;
            return;
        }

        if (!hasTriggeredControl) {
            if (deltaY < -30 && fabs(deltaY) > fabs(deltaX)) {
                hasTriggeredControl = YES;
                playImpactFeedback();
                [self activateVolumeMode];
                return;
            }

            if (fabs(deltaX) > 30 || fabs(deltaY) > 50) {
                hasTriggeredControl = YES;
                playImpactFeedback();

                if (fabs(deltaY) > fabs(deltaX) && deltaY > 50) {
                    shouldHideOnSwipeUp = YES;
                    safe_log("[MusicWidget] 下滑距离超过50，将在松手后隐藏");
                } else if (fabs(deltaX) > fabs(deltaY) && fabs(deltaX) > 30) {
                    if (deltaX > 0) {
                        MRMediaRemoteSendCommand(MRMediaRemoteCommandNextTrack, nil);
                        safe_log("[MusicWidget] 右滑：下一首");
                    } else {
                        MRMediaRemoteSendCommand(MRMediaRemoteCommandPreviousTrack, nil);
                        safe_log("[MusicWidget] 左滑：上一首");
                    }
                }
            }
        } else {
            shouldHideOnSwipeUp = (fabs(deltaY) > fabs(deltaX) && deltaY > 50);
        }
    } else if (pan.state == UIGestureRecognizerStateEnded || pan.state == UIGestureRecognizerStateCancelled) {
        BOOL didFinishMove = didMoveWindowDuringPan || isLongPressActive;

        if (self.isVolumeMode) {
            [self deactivateVolumeMode];
            [UIView animateWithDuration:0.25 animations:^{
                window.frame = CGRectMake(currentOrigin.x, currentOrigin.y, kWindowSize, kWindowSize);
            }];
            hasTriggeredControl = NO;
            shouldHideOnSwipeUp = NO;
            didMoveWindowDuringPan = NO;
            return;
        }

        if (shouldHideOnSwipeUp && !didFinishMove) {
            floatWindow.hidden = YES;
            wasPlayingInfoAvailable = NO;
            userSuppressedAutoShow = YES;
            safe_log("[MusicWidget] 下滑松手，隐藏悬浮窗");
        }

        if (didFinishMove) {
            CGRect newFrame = constrainFrameToScreen(window.frame);
            window.frame = newFrame;
            currentOrigin = newFrame.origin;
            saveCurrentOrigin();
            safe_log("[MusicWidget] 长按拖拽结束，新原点已保存");
        } else {
            CGRect targetFrame = constrainFrameToScreen(CGRectMake(currentOrigin.x, currentOrigin.y, kWindowSize, kWindowSize));
            currentOrigin = targetFrame.origin;
            [UIView animateWithDuration:0.25 animations:^{
                window.frame = targetFrame;
            }];
        }

        isLongPressActive = NO;
        hasTriggeredControl = NO;
        shouldHideOnSwipeUp = NO;
        didMoveWindowDuringPan = NO;
    }
}

- (void)activateVolumeMode {
    if (self.isVolumeMode) return;
    self.isVolumeMode = YES;

    UIWindow *window = self.targetWindow;
    if (!window) return;

    UIView *contentView = window.rootViewController.view ?: window;
    CGRect volumeFrame = CGRectMake(0, 0, kWindowSize, 150);
    self.volumeView = [[MediaFloaterVolumeView alloc] initWithFrame:volumeFrame];
    self.volumeView.alpha = 0;
    self.volumeView.transform = CGAffineTransformMakeScale(0.8, 0.8);
    [contentView addSubview:self.volumeView];

    self.volumeView.center = panStartLocationInWindow;

    float sysVol = 0.5;
    AVSystemController *av = [NSClassFromString(@"AVSystemController") sharedAVSystemController];
    [av getVolume:&sysVol forCategory:@"Audio/Video"];
    [self.volumeView setVolume:sysVol animated:NO];
    self.initialVolume = sysVol;
    self.initialFingerY = panStartLocation.y;

    [UIView animateWithDuration:0.25 animations:^{
        albumArtView.alpha = 0;
        albumArtView.transform = CGAffineTransformMakeScale(0.8, 0.8);
        self.volumeView.alpha = 1;
        self.volumeView.transform = CGAffineTransformIdentity;
    }];
}

- (void)deactivateVolumeMode {
    if (!self.isVolumeMode) return;
    self.isVolumeMode = NO;

    [UIView animateWithDuration:0.25 animations:^{
        self.volumeView.alpha = 0;
        self.volumeView.transform = CGAffineTransformMakeScale(0.8, 0.8);
        albumArtView.alpha = 1;
        albumArtView.transform = CGAffineTransformIdentity;
    } completion:^(BOOL finished) {
        [self.volumeView removeFromSuperview];
        self.volumeView = nil;
    }];
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer {
    if ([gestureRecognizer isKindOfClass:[UITapGestureRecognizer class]]) {
        return !isLongPressActive && !self.isVolumeMode;
    }
    return YES;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    BOOL isPanAndLongPress =
        ([gestureRecognizer isKindOfClass:[UIPanGestureRecognizer class]] && [otherGestureRecognizer isKindOfClass:[UILongPressGestureRecognizer class]]) ||
        ([gestureRecognizer isKindOfClass:[UILongPressGestureRecognizer class]] && [otherGestureRecognizer isKindOfClass:[UIPanGestureRecognizer class]]);
    return isPanAndLongPress;
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
    [albumArtView addGestureRecognizer:tap];

    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:handler action:@selector(handlePan:)];
    [albumArtView addGestureRecognizer:pan];

    UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:handler action:@selector(handleLongPress:)];
    longPress.minimumPressDuration = 0.3;
    [albumArtView addGestureRecognizer:longPress];

    pan.delegate = handler;
    longPress.delegate = handler;
    tap.delegate = handler;

    safe_log("[MusicWidget] 悬浮窗创建成功，scene 已绑定，手势已注册");
}

static void registerLifecycleObservers(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSNotificationCenter *center = [NSNotificationCenter defaultCenter];

        void (^rebuildBlock)(NSNotification *) = ^(NSNotification *note) {
            safe_log("[MusicWidget] 收到生命周期激活事件，重新检查悬浮窗");
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

%ctor {
    registerLifecycleObservers();
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        ensureFloatWindowReady();
    });
    safe_log("[MusicWidget] 插件已加载，等待播放信息...");
}