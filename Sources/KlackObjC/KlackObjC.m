#import "include/KlackObjC.h"

BOOL KlackRunCatchingExceptions(void (NS_NOESCAPE ^block)(void),
                                NSError *_Nullable *_Nullable error) {
    @try {
        block();
        return YES;
    } @catch (NSException *exception) {
        if (error) {
            NSMutableDictionary *info = [NSMutableDictionary dictionary];
            info[NSLocalizedDescriptionKey] = exception.reason ?: @"unknown exception";
            info[@"name"] = exception.name ?: @"unknown";
            *error = [NSError errorWithDomain:@"com.vinaypathak.klack.ObjCException"
                                         code:0
                                     userInfo:info];
        }
        return NO;
    }
}
