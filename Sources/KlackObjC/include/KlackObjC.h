#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Runs `block`, converting any Objective-C exception it raises into an
/// NSError return instead of letting it unwind.
///
/// This exists for AVAudioEngine. Its connect/start calls raise NSException
/// on invalid state -- notably while the output device is being swapped
/// (headphones, Bluetooth, sleep/wake). Swift cannot catch NSException, so
/// such a throw terminates the whole app: Klack simply disappears and looks
/// like it "stopped working" until it's launched again.
///
/// Returns YES on success, NO if an exception was caught.
BOOL KlackRunCatchingExceptions(void (NS_NOESCAPE ^block)(void),
                                NSError *_Nullable *_Nullable error);

NS_ASSUME_NONNULL_END
