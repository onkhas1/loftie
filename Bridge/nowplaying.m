// Мост к «Сейчас играет» (MediaRemote).
// С macOS 15.4 эти данные отдаются только системным процессам, поэтому
// библиотеку загружает /usr/bin/perl (см. nowplaying.pl), а Loftie читает её вывод.
// Без LOFTIE_CMD печатает JSON с треком; с LOFTIE_CMD=2/4/5 шлёт команду плееру.
#import <Foundation/Foundation.h>
#include <dlfcn.h>
#include <stdlib.h>

typedef void (*GetInfoFn)(dispatch_queue_t, void (^)(CFDictionaryRef));
typedef void (*GetPlayingFn)(dispatch_queue_t, void (^)(Boolean));
typedef void (*GetClientFn)(dispatch_queue_t, void (^)(id));
typedef Boolean (*SendFn)(unsigned int, CFDictionaryRef);
typedef CFStringRef (*ClientIdFn)(id);

// Сигнатура как у XS-функции perl, аргументы не нужны
void loftie_now_playing(void *perl, void *cv) {
    @autoreleasepool {
        void *mr = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW);
        if (!mr) { printf("{}\n"); fflush(stdout); return; }

        const char *cmd = getenv("LOFTIE_CMD");
        if (cmd) {
            SendFn send = (SendFn)dlsym(mr, "MRMediaRemoteSendCommand");
            Boolean ok = send ? send((unsigned int)atoi(cmd), NULL) : false;
            // Команда уходит асинхронно: не завершаемся, пока macOS её не доставит
            CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.5, false);
            printf("{\"sent\":%s}\n", ok ? "true" : "false");
            fflush(stdout);
            return;
        }

        GetInfoFn getInfo = (GetInfoFn)dlsym(mr, "MRMediaRemoteGetNowPlayingInfo");
        GetPlayingFn getPlaying = (GetPlayingFn)dlsym(mr, "MRMediaRemoteGetNowPlayingApplicationIsPlaying");
        GetClientFn getClient = (GetClientFn)dlsym(mr, "MRMediaRemoteGetNowPlayingClient");
        ClientIdFn clientId = (ClientIdFn)dlsym(mr, "MRNowPlayingClientGetBundleIdentifier");
        ClientIdFn parentId = (ClientIdFn)dlsym(mr, "MRNowPlayingClientGetParentAppBundleIdentifier");

        NSMutableDictionary *out = [NSMutableDictionary dictionary];
        dispatch_queue_t queue = dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0);

        if (getInfo) {
            dispatch_semaphore_t done = dispatch_semaphore_create(0);
            getInfo(queue, ^(CFDictionaryRef raw) {
                NSDictionary *info = (__bridge NSDictionary *)raw;
                id title = info[@"kMRMediaRemoteNowPlayingInfoTitle"];
                id artist = info[@"kMRMediaRemoteNowPlayingInfoArtist"];
                id album = info[@"kMRMediaRemoteNowPlayingInfoAlbum"];
                id duration = info[@"kMRMediaRemoteNowPlayingInfoDuration"];
                id elapsed = info[@"kMRMediaRemoteNowPlayingInfoElapsedTime"];
                id rate = info[@"kMRMediaRemoteNowPlayingInfoPlaybackRate"];
                id stamp = info[@"kMRMediaRemoteNowPlayingInfoTimestamp"];
                NSData *art = info[@"kMRMediaRemoteNowPlayingInfoArtworkData"];
                if ([title isKindOfClass:NSString.class]) out[@"title"] = title;
                if ([artist isKindOfClass:NSString.class]) out[@"artist"] = artist;
                if ([album isKindOfClass:NSString.class]) out[@"album"] = album;
                if ([duration isKindOfClass:NSNumber.class]) out[@"duration"] = duration;
                if ([elapsed isKindOfClass:NSNumber.class]) out[@"elapsed"] = elapsed;
                if ([rate isKindOfClass:NSNumber.class]) out[@"rate"] = rate;
                if ([stamp isKindOfClass:NSDate.class]) out[@"timestamp"] = @([(NSDate *)stamp timeIntervalSince1970]);
                if ([art isKindOfClass:NSData.class] && art.length < 2000000) out[@"artwork"] = [art base64EncodedStringWithOptions:0];
                dispatch_semaphore_signal(done);
            });
            dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, 1500 * NSEC_PER_MSEC));
        }
        if (getPlaying) {
            dispatch_semaphore_t done = dispatch_semaphore_create(0);
            getPlaying(queue, ^(Boolean playing) {
                out[@"playing"] = @(playing);
                dispatch_semaphore_signal(done);
            });
            dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, 1000 * NSEC_PER_MSEC));
        }
        if (getClient && clientId) {
            dispatch_semaphore_t done = dispatch_semaphore_create(0);
            getClient(queue, ^(id client) {
                if (client) {
                    CFStringRef parent = parentId ? parentId(client) : NULL;
                    CFStringRef bundle = clientId(client);
                    CFStringRef chosen = parent ? parent : bundle;
                    if (chosen) out[@"bundle"] = (__bridge NSString *)chosen;
                }
                dispatch_semaphore_signal(done);
            });
            dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, 1000 * NSEC_PER_MSEC));
        }

        NSData *json = [NSJSONSerialization dataWithJSONObject:out options:0 error:nil];
        fwrite(json.bytes, 1, json.length, stdout);
        printf("\n");
        fflush(stdout);
    }
}
