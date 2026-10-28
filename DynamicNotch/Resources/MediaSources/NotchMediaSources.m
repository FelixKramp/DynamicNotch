// NotchMediaSources: listet alle Now-Playing-Apps und steuert jede einzeln.
//
// MediaRemote antwortet seit macOS 15.4 nur noch Apple-signierten Prozessen.
// Deshalb wird diese Bibliothek wie der MediaRemoteAdapter über /usr/bin/perl
// geladen (siehe notch-media-sources.pl).
//
// Signaturen der privaten Funktionen per Disassembly auf macOS 27 geprüft.
//
// Gezielte Befehle an eine bestimmte App (SendCommandToPlayer/-ToApp/-ToClient)
// leitet macOS von außen stillschweigend an die aktive App weiter. Darum
// steuert nms_send nur die aktive App und meldet sonst Exit-Code 3; die App
// fällt dann auf einen Tastendruck zurück (MediaSourcesViewModel).

#import <Foundation/Foundation.h>
#include <dlfcn.h>

@interface NSObject (NotchMediaSourcesPlayerPath)
- (id)initWithOrigin:(id)origin client:(id)client player:(id)player;
@end

typedef void (^NMSArrayBlock)(id array);
typedef void (^NMSInfoBlock)(id info, void *error);
typedef void (^NMSStateBlock)(unsigned int state);
typedef void (^NMSResultBlock)(id result);

static void *nms_symbol(const char *name) {
    static void *handle;
    if (!handle) {
        handle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW);
    }
    return handle ? dlsym(handle, name) : NULL;
}

static const NSTimeInterval kNMSTimeout = 2.0;

static void nms_wait(dispatch_semaphore_t semaphore) {
    dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kNMSTimeout * NSEC_PER_SEC)));
}

static void nms_fail(NSString *message) {
    fprintf(stderr, "%s\n", message.UTF8String);
    exit(1);
}

static NSArray *nms_clients(dispatch_queue_t queue) {
    void (*getClients)(dispatch_queue_t, NMSArrayBlock) = nms_symbol("MRMediaRemoteGetNowPlayingClients");
    if (!getClients) nms_fail(@"MRMediaRemoteGetNowPlayingClients not found");

    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    __block NSArray *clients = @[];
    getClients(queue, ^(id array) {
        if ([array isKindOfClass:[NSArray class]]) clients = [array copy];
        dispatch_semaphore_signal(semaphore);
    });
    nms_wait(semaphore);
    return clients;
}

static id nms_player_path(id client) {
    id (*localOrigin)(void) = nms_symbol("MRMediaRemoteGetLocalOrigin");
    Class pathClass = NSClassFromString(@"MRPlayerPath");
    if (!localOrigin || !pathClass) nms_fail(@"MRPlayerPath not available");
    return [[pathClass alloc] initWithOrigin:localOrigin() client:client player:nil];
}

static NSString *nms_bundle_identifier(id client) {
    NSString *(*getBundleIdentifier)(id) = nms_symbol("MRNowPlayingClientGetBundleIdentifier");
    return getBundleIdentifier ? getBundleIdentifier(client) : nil;
}

static NSString *nms_now_playing_bundle_identifier(dispatch_queue_t queue) {
    void (*getClient)(dispatch_queue_t, NMSArrayBlock) = nms_symbol("MRMediaRemoteGetNowPlayingClient");
    if (!getClient) return nil;

    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    __block NSString *bundleIdentifier = nil;
    getClient(queue, ^(id client) {
        if (client) bundleIdentifier = nms_bundle_identifier(client);
        dispatch_semaphore_signal(semaphore);
    });
    nms_wait(semaphore);
    return bundleIdentifier;
}

static id nms_json_value(id value) {
    if (!value) return [NSNull null];
    if ([value isKindOfClass:[NSDate class]]) return @([(NSDate *)value timeIntervalSince1970]);
    if ([value isKindOfClass:[NSString class]] || [value isKindOfClass:[NSNumber class]]) return value;
    return [NSNull null];
}

static NSDictionary *nms_describe(id client, dispatch_queue_t queue, NSString *nowPlayingBundleIdentifier) {
    NSString *(*getParent)(id) = nms_symbol("MRNowPlayingClientGetParentAppBundleIdentifier");
    NSString *(*getDisplayName)(id) = nms_symbol("MRNowPlayingClientGetDisplayName");
    int (*getPID)(id) = nms_symbol("MRNowPlayingClientGetProcessIdentifier");
    void (*getInfo)(id, id, dispatch_queue_t, NMSInfoBlock) = nms_symbol("MRMediaRemoteGetNowPlayingInfoForPlayer");
    void (*getState)(id, dispatch_queue_t, NMSStateBlock) = nms_symbol("MRMediaRemoteGetPlaybackStateForPlayer");

    id path = nms_player_path(client);
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

    __block NSDictionary *info = @{};
    if (getInfo) {
        getInfo(path, nil, queue, ^(id result, void *error) {
            if ([result isKindOfClass:[NSDictionary class]]) info = [result copy];
            dispatch_semaphore_signal(semaphore);
        });
        nms_wait(semaphore);
    }

    // 1 = spielt, 2 = pausiert, 3 = gestoppt, 0 = unbekannt
    __block unsigned int state = 0;
    if (getState) {
        getState(path, queue, ^(unsigned int result) {
            state = result;
            dispatch_semaphore_signal(semaphore);
        });
        nms_wait(semaphore);
    }

    NSString *bundleIdentifier = nms_bundle_identifier(client);
    return @{
        @"bundleIdentifier": nms_json_value(bundleIdentifier),
        @"isNowPlaying": @([bundleIdentifier isEqualToString:nowPlayingBundleIdentifier]),
        @"parentBundleIdentifier": nms_json_value(getParent ? getParent(client) : nil),
        @"displayName": nms_json_value(getDisplayName ? getDisplayName(client) : nil),
        @"processIdentifier": @(getPID ? getPID(client) : 0),
        @"playbackState": @(state),
        @"title": nms_json_value(info[@"kMRMediaRemoteNowPlayingInfoTitle"]),
        @"artist": nms_json_value(info[@"kMRMediaRemoteNowPlayingInfoArtist"]),
        @"album": nms_json_value(info[@"kMRMediaRemoteNowPlayingInfoAlbum"]),
        @"duration": nms_json_value(info[@"kMRMediaRemoteNowPlayingInfoDuration"]),
        @"elapsedTime": nms_json_value(info[@"kMRMediaRemoteNowPlayingInfoElapsedTime"]),
        @"playbackRate": nms_json_value(info[@"kMRMediaRemoteNowPlayingInfoPlaybackRate"]),
        @"timestamp": nms_json_value(info[@"kMRMediaRemoteNowPlayingInfoTimestamp"]),
    };
}

static void nms_print_json(id object) {
    NSError *error = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:object options:0 error:&error];
    if (!data) nms_fail([NSString stringWithFormat:@"JSON error: %@", error]);
    fwrite(data.bytes, 1, data.length, stdout);
    fputc('\n', stdout);
    fflush(stdout);
}

void nms_list(void) {
    @autoreleasepool {
        dispatch_queue_t queue = dispatch_queue_create("notch.mediasources", DISPATCH_QUEUE_SERIAL);
        NSString *nowPlaying = nms_now_playing_bundle_identifier(queue);
        NSMutableArray *sources = [NSMutableArray array];
        for (id client in nms_clients(queue)) {
            [sources addObject:nms_describe(client, queue, nowPlaying)];
        }
        nms_print_json(sources);
    }
}

// Liest NMS_BUNDLE_IDENTIFIER und NMS_COMMAND (MRCommand: 0 play, 1 pause,
// 2 toggle, 4 next, 5 previous) aus der Umgebung.
void nms_send(void) {
    @autoreleasepool {
        const char *bundleValue = getenv("NMS_BUNDLE_IDENTIFIER");
        const char *commandValue = getenv("NMS_COMMAND");
        if (!bundleValue || !commandValue) nms_fail(@"NMS_BUNDLE_IDENTIFIER and NMS_COMMAND required");

        NSString *bundleIdentifier = @(bundleValue);
        unsigned int command = (unsigned int)atoi(commandValue);
        if (command > 5 || command == 3) nms_fail(@"Unsupported command");

        bool (*sendCommand)(unsigned int, id) = nms_symbol("MRMediaRemoteSendCommand");
        if (!sendCommand) nms_fail(@"MRMediaRemoteSendCommand not found");

        dispatch_queue_t queue = dispatch_queue_create("notch.mediasources", DISPATCH_QUEUE_SERIAL);
        if (![nms_now_playing_bundle_identifier(queue) isEqualToString:bundleIdentifier]) {
            fprintf(stderr, "%s is not the now playing app\n", bundleValue);
            exit(3);
        }
        if (!sendCommand(command, nil)) nms_fail(@"Command failed");
    }
}
