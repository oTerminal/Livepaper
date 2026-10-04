// Declarations of the private wallpaper-extension API, for WallpaperAgentBridge
// alone. Adapted from Phosphene's
// WallpaperExtension-Bridging-Header.h (MIT, (c) 2026 kageroumado,
// https://github.com/kageroumado/phosphene); see NOTICE at the repository root.
//
// The XPC payload classes live in WallpaperExtensionKit.framework and are loaded
// with dlopen at run time; nothing here links against a private framework.

#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>

NS_ASSUME_NONNULL_BEGIN

// Remote rendering: a CAContext whose id WallpaperAgent hosts in a CALayerHost.
// QuartzCore exports the class, so it links; it is weakly imported so that a
// macOS without it still launches the extension, and the self-check names it.
__attribute__((weak_import))
@interface CAContext : NSObject
@property (readonly) unsigned int contextId;
@property (retain, nullable) CALayer *layer;
+ (nullable id)remoteContextWithOptions:(nullable NSDictionary *)options;
- (void)invalidate;
@end

// Extension -> WallpaperAgent.
@protocol WallpaperExtensionProxyXPCProtocol <NSObject>
- (void)pingWithId:(id _Nullable)anId;
- (void)updateSettingsViewModels:(id _Nullable)models reply:(void (NS_SWIFT_SENDABLE ^ _Nonnull)(NSError * _Nullable))reply;
- (void)requestReadOnlyAccessTo:(id _Nullable)url reply:(void (NS_SWIFT_SENDABLE ^ _Nonnull)(id _Nullable))reply;
- (void)invalidateSnapshotsWithReply:(void (NS_SWIFT_SENDABLE ^ _Nonnull)(NSError * _Nullable))reply;
@end

// WallpaperAgent -> extension. A reply block may be called from any thread, once,
// which is what NS_SWIFT_SENDABLE says to Swift.
@protocol WallpaperExtensionXPCProtocol <NSObject>
- (void)acquireWithId:(id _Nullable)anId request:(id _Nullable)request reply:(void (NS_SWIFT_SENDABLE ^ _Nonnull)(id _Nullable, NSError * _Nullable))reply;
- (void)updateWithId:(id _Nullable)anId request:(id _Nullable)request reply:(void (NS_SWIFT_SENDABLE ^ _Nonnull)(NSError * _Nullable))reply;
- (void)invalidateWithId:(id _Nullable)anId reply:(void (NS_SWIFT_SENDABLE ^ _Nonnull)(NSError * _Nullable))reply;
- (void)snapshotWithId:(id _Nullable)anId reply:(void (NS_SWIFT_SENDABLE ^ _Nonnull)(id _Nullable, NSError * _Nullable))reply;
- (void)provideSettingsViewModelsWithContentTypes:(id _Nullable)types reply:(void (NS_SWIFT_SENDABLE ^ _Nonnull)(id _Nullable, NSError * _Nullable))reply;
- (void)addChoiceRequestWithChoiceRequest:(id _Nullable)request onBehalfOfProcess:(id _Nullable)process reply:(void (NS_SWIFT_SENDABLE ^ _Nonnull)(id _Nullable, NSError * _Nullable))reply;
- (void)removeChoiceRequestWithChoiceRequest:(id _Nullable)request reply:(void (NS_SWIFT_SENDABLE ^ _Nonnull)(NSError * _Nullable))reply;
- (void)selectedChoicesDidChangeFor:(id _Nullable)anId reply:(void (NS_SWIFT_SENDABLE ^ _Nonnull)(NSError * _Nullable))reply;
- (void)invokeContextMenuActionWithMenuItemID:(id _Nullable)menuItemID groupItemID:(id _Nullable)groupItemID reply:(void (NS_SWIFT_SENDABLE ^ _Nonnull)(NSError * _Nullable))reply;
- (void)isChoiceDownloadedWith:(id _Nullable)choiceID reply:(void (NS_SWIFT_SENDABLE ^ _Nonnull)(BOOL, NSError * _Nullable))reply;
- (id _Nullable)downloadWithChoiceID:(id _Nullable)choiceID reply:(void (NS_SWIFT_SENDABLE ^ _Nonnull)(NSError * _Nullable))reply;
- (void)pauseDownloadFor:(id _Nullable)choiceID reply:(void (NS_SWIFT_SENDABLE ^ _Nonnull)(NSError * _Nullable))reply;
- (void)cancelDownloadFor:(id _Nullable)choiceID reply:(void (NS_SWIFT_SENDABLE ^ _Nonnull)(NSError * _Nullable))reply;
- (void)resumeDownloadFor:(id _Nullable)choiceID reply:(void (NS_SWIFT_SENDABLE ^ _Nonnull)(NSError * _Nullable))reply;
- (void)removeDownloadFor:(id _Nullable)choiceID reply:(void (NS_SWIFT_SENDABLE ^ _Nonnull)(NSError * _Nullable))reply;
- (void)migrateSelectedChoiceFor:(id _Nullable)anId reply:(void (NS_SWIFT_SENDABLE ^ _Nonnull)(id _Nullable, NSError * _Nullable))reply;
- (void)migrateFrom:(id _Nullable)from to:(id _Nullable)to reply:(void (NS_SWIFT_SENDABLE ^ _Nonnull)(NSError * _Nullable))reply;
- (void)skipShuffledContentWithId:(id _Nullable)anId reply:(void (NS_SWIFT_SENDABLE ^ _Nonnull)(NSError * _Nullable))reply;
- (void)canSkipShuffledContentWithId:(id _Nullable)anId reply:(void (NS_SWIFT_SENDABLE ^ _Nonnull)(BOOL, NSError * _Nullable))reply;
- (void)handleDebugRequestFor:(id _Nullable)request reply:(void (NS_SWIFT_SENDABLE ^ _Nonnull)(id _Nullable, NSError * _Nullable))reply;
- (void)handleNotificationWithNamed:(id _Nullable)name reply:(void (NS_SWIFT_SENDABLE ^ _Nonnull)(NSError * _Nullable))reply;
@end

NS_ASSUME_NONNULL_END
