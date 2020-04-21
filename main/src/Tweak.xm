#import <AVFoundation/AVFoundation.h>
#import <version.h>
#import <substrate.h>
#include <dlfcn.h>
#import "FBSystemService.h"
#import "SpringBoard.h"
#import "Globals.h"
#import "Frame.h"
#import "UIView+.h"

// MARK: Main Tweak

void const *playerLayerKey;

// Check for folder access, otherwise warn user.
void checkResourceFolder(UIViewController *presenterVC) {
	NSString *testFile = @"/var/mobile/Documents/com.ZX02.Frame/.test.txt";

	// Try to write to a test file.
	NSString *str = @"Please do not delete this folder.";
	NSError *err;
	[str writeToFile: testFile atomically: true encoding: NSUTF8StringEncoding error: &err];

	if (err != nil) {
		UIAlertController *alertVC = [UIAlertController alertControllerWithTitle: @"Frame - Tweak"
													message: @"Resource folder can't be accessed."
													preferredStyle: UIAlertControllerStyleAlert];
		[alertVC addAction: [UIAlertAction actionWithTitle: @"Details" style: UIAlertActionStyleDefault handler: ^(UIAlertAction *action) {
			[[UIApplication sharedApplication] openURL: [NSURL URLWithString: @"https://zerui18.github.io/ZX02#err=frame.res404"] options:@{} completionHandler: nil];
		}]];
		[alertVC addAction: [UIAlertAction actionWithTitle: @"Ignore" style: UIAlertActionStyleCancel handler: nil]];
		[presenterVC presentViewController: alertVC animated: true completion: nil];
	}
}

%group Tweak

	// Helper function that sets up wallpaper player in the given wallpaperView.
	void setupWallpaperPlayer(SBFWallpaperView *wallpaperView, bool isLockscreenView) {
		// Attempts to retrieve associated AVPlayerLayer.
		AVPlayerLayer *playerLayer = (AVPlayerLayer *) objc_getAssociatedObject(wallpaperView, &playerLayerKey);
		
		// No existing playerLayer? Init
		if (playerLayer == nil) {

			// Setup Player.
			Frame *player = [%c(Frame) shared];
			// Note: Don't add wallpaperView into .contentView as it's irregularly framed.
			playerLayer = [player addInView: wallpaperView isLockscreen: isLockscreenView];
			objc_setAssociatedObject(wallpaperView, &playerLayerKey, playerLayer, OBJC_ASSOCIATION_RETAIN);

		}
	}

	%hook SBWallpaperController
		// Point of setup for wallpaper players.
		+ (id) sharedInstance {
			SBWallpaperController *s = %orig;

			// We don't need to ensure singular call as the setup function checks if the provided view has been configured.
			if (s.lockscreenWallpaperView != nil && s.homescreenWallpaperView != nil) {
				setupWallpaperPlayer(s.lockscreenWallpaperView, true);
				setupWallpaperPlayer(s.homescreenWallpaperView, false);
			}
			else if (s.sharedWallpaperView != nil) {
				setupWallpaperPlayer(s.sharedWallpaperView, false);
			}

			// We will also check if the user's configuration's erroneous.
			static bool hasAlerted;
 			
			Frame *player = [%c(Frame) shared];
			// Alert user if Frame is active and settings is incompatible.
			if (player.isTweakEnabled) {
				if ([player requiresDifferentSystemWallpapers] && s.sharedWallpaperView != nil) {
					// Alert (once).
					if (hasAlerted) return s;
					// Setup alertVC and present.
					UIAlertController *alertVC = [UIAlertController alertControllerWithTitle: @"Frame - Tweak"
													message: @"You have chosen different videos for lockscreen & homescreen, but you will need to set different system wallpapers for lockscreen & homescreen for this to take effect."
													preferredStyle: UIAlertControllerStyleAlert];
					[alertVC addAction: [UIAlertAction actionWithTitle: @"OK" style: UIAlertActionStyleDefault handler: nil]];
					UIViewController *presenterVC = UIApplication.sharedApplication.windows.firstObject.rootViewController;
					if (presenterVC != nil) {
						[presenterVC presentViewController: alertVC animated: true completion: nil], hasAlerted = true;
						hasAlerted = true;
					}
				}
			}

			return s;
		}
	%end

	%hook SBFWallpaperView

		- (void) layoutSubviews {
			%orig;

			// Insert point for coversheet window, which is not covered by the SBWallpaperController hook.
			if ([self.window isKindOfClass: [%c(SBCoverSheetWindow) class]]) {
				setupWallpaperPlayer(self, true);
			}

			// General operation of re-positioning the playerLayer.
			// Attempts to retrieve associated AVPlayerLayer.
			AVPlayerLayer *playerLayer = (AVPlayerLayer *) objc_getAssociatedObject(self, &playerLayerKey);

			if (playerLayer != nil) {
				// Send playerLayer to front and match its frame to that of the current view.
				// Note: for compatibility with SpringArtwork, we let SAViewController's view's layer stay atop :)
				CALayer *saLayer;
				for (UIView *view in self.subviews) {
					if ([view.nextResponder isKindOfClass: [%c(SAViewController) class]]) {
						saLayer = view.layer;
						break;
					}
				}
				
				if (saLayer != nil)
					[self.layer insertSublayer: playerLayer below: saLayer];
				else
					[self.layer addSublayer: playerLayer];

				playerLayer.frame = self.bounds;
			}
		}
	
	%end

	// Rework the blue effect of folders.
	// By default iOS seems to render the blurred images "manually" (without using UIVisualEffectView)
	// and using a snapshot of the wallpaper.
	// The simplest way to adapt this to our video bg is to replace the stock view that renders the blurred image
	// with an actual UIVisualEffectView

	%hook SBWallpaperEffectView 

		-(void) didMoveToWindow {
			%orig;

			// Repairs the reachability blur view when activated from the home screen.
			if (!isInApp && [self.window isKindOfClass: [%c(SBReachabilityWindow) class]]) {
				// Remove the stock blur view.
				self.subviews.firstObject &&
					(self.subviews.firstObject.hidden = true);
				UIView *newBlurView;
				if (@available(iOS 13.0, *))
					newBlurView = [[UIVisualEffectView alloc] initWithEffect: [UIBlurEffect effectWithStyle: UIBlurEffectStyleSystemUltraThinMaterial]];
				else
					newBlurView = [[UIVisualEffectView alloc] initWithEffect: [UIBlurEffect effectWithStyle: UIBlurEffectStyleRegular]];
				newBlurView.frame = self.bounds;
				[self addSubview: newBlurView];
				return %orig;
			}

			// Only apply fix for the following cases:
			// Wallpaper style 29 -> icon component blur
			// Wallpaper style 12 -> SBDockView's underlying blur (iOS <= 12)
			if (self.wallpaperStyle != 29 && self.wallpaperStyle != 12)
				return;
			// Hide the stock blur effect render.
			self.blurView &&
				self.blurView.subviews.firstObject &&
					(self.blurView.subviews.firstObject.hidden = true);

			UIView *newBlurView;
			if (@available(iOS 13.0, *))
				newBlurView = [[UIVisualEffectView alloc] initWithEffect: [UIBlurEffect effectWithStyle: UIBlurEffectStyleSystemUltraThinMaterial]];
			else
				newBlurView = [[UIVisualEffectView alloc] initWithEffect: [UIBlurEffect effectWithStyle: UIBlurEffectStyleRegular]];
			
			// Add our blur view to self.blurView (system's fake blur).
			newBlurView.frame = self.blurView.bounds;
			newBlurView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
			[self.blurView addSubview: newBlurView];
		}
	%end

	// Coordinate the Frame with SpringBoard.
	// Pause player when an application opens.
	// Resume player when the homescreen is shown.

	%hook SpringBoard

		// Control for enter / exit app.
		- (void) frontDisplayDidChange: (id) newDisplay {
			%orig;
			Frame *player = [%c(Frame) shared];
			if (newDisplay != nil) {
				// Only pause if we're entering an app and not just entering app-switcher.
				if (!isInApp) {
					// Entered app.
					isInApp = true;
					if (isOnLockscreen) {
						// If the user immediately swiped down and now we're on lockscreen.
						[player pauseHomescreen];
					}
					else {
						// Thankfully we're still in the app.
						[player pauseHomescreen];
						[player pauseSharedPlayer];
					}
				}
			}
			else if (isInApp) {
				// Left app.
				isInApp = false;
				[player playHomescreen];
			}
		}
	%end

	// Control for Siri.
	// This is in place of listening for audio session interruption notifications, which are not sent properly.
	%hook SBAssistantRootViewController
		- (void) viewWillDisappear: (BOOL) animated {
			%orig;

			Frame *player = [%c(Frame) shared];
			if (isOnLockscreen) // Play lockscreen.
				[player playLockscreen];
			else if (!isInApp || !player.pauseInApps) // Play homescreen if we're not in app OR player doesn't pause in apps.
				[player playHomescreen];
		}
	%end

	// Control for home.
	// Fastest route yet found for all users.
	%hook SBLayoutStateTransitionContext
		- (id) initWithWorkspaceTransaction: (id) arg1 {
			SBLayoutStateTransitionContext *s = %orig;
			SBLayoutState *from = s.fromLayoutState;
			SBLayoutState *to = s.toLayoutState;
			Frame *player = [%c(Frame) shared];
			if (from.elements != nil && to.elements == nil) {
				// Leaving an app.
				if (isInApp) {
					isInApp = NO;
					[player playHomescreen];
				}
			}
			return s;
		}
	%end

	// Sleep / wake controls.
	%hook FBDisplayLayoutTransition

		// More reliable control for sleep / wait.
		// Accounts for cases where no wake animation is required.
		-(void) setBacklightLevel: (long long) level {
			%orig(level);
			// Determine whether screen is on.
			bool isAwake = level != 0.0;
			// Update global var.
			isAsleep = !isAwake;
			// Play / pause.
			Frame *player = [%c(Frame) shared];
			if (isAwake) {
				[player playLockscreen];
			}
			else {
				[player pause];
			}
		}
	
	%end

	// Control for lockscreen & coversheet.
	// Resume player whenever coversheet will be shown.
	%hook CSCoverSheetViewController

		// The cases for play/pause are divided into the will/did appear/disappear methods,
		// to ensure that the wallpaper will begin playing as early as possible
		// and stop playing as late as possible.

		- (void) viewWillAppear: (BOOL) animated {
			%orig;
			isOnLockscreen = true;
			Frame *player = [%c(Frame) shared];
			// Ignore if this is triggered on sleep.
			// Otherwise eagerly play.
			if (!isAsleep) {
				[player playLockscreen];
			}
		}

		- (void) viewDidAppear: (BOOL) animated {
			%orig;
			Frame *player = [%c(Frame) shared];
			// Ignore if this is triggered on sleep.
			if (!isAsleep) {
				[player pauseHomescreen];
			}
		}

		- (void) viewWillDisappear: (BOOL) animated {
			%orig;
			Frame *player = [%c(Frame) shared];
			if (!player.pauseInApps || !isInApp) {
				[player playHomescreen];
			}
		}

		- (void) viewDidDisappear: (BOOL) animated {
			%orig;
			isOnLockscreen = false;
			Frame *player = [%c(Frame) shared];
			[player pauseLockscreen];
			// Additonal check to prevent situations where a shared player is set
			// and when the user dismisses the cover sheet it doesn't stop playing.
			if (isInApp && player.pauseInApps)
				[player pauseSharedPlayer];				
		}

	%end

	%hook SBHomeScreenViewController

		- (void) viewDidAppear: (bool) animated {
			%orig;
						
			// Here we check the resource folder and alert user if there's an error.
			static bool checkedFolder = false;
			if (!checkedFolder) {
				checkResourceFolder(self);
				checkedFolder = true;
			}
		}

	%end

%end

// Group of iOS < 13 specific hooks.
%group Fallback

	// Achieves the same effect as hooking CSCoverSheet, but on iOS <= 12.
	%hook SBDashBoardViewController

		// The cases for play/pause are divided into the will/did appear/disappear methods,
		// to ensure that the wallpaper will begin playing as early as possible
		// and stop playing as late as possible.

		- (void) viewWillAppear: (BOOL) animated {
			%orig;
			isOnLockscreen = true;
			Frame *player = [%c(Frame) shared];
			// Ignore if this is triggered on sleep.
			// Otherwise eagerly play.
			if (!isAsleep) {
				[player playLockscreen];
			}
		}

		- (void) viewDidAppear: (BOOL) animated {
			%orig;
			Frame *player = [%c(Frame) shared];
			// Ignore if this is triggered on sleep.
			if (!isAsleep) {
				[player pauseHomescreen];
			}
		}

		- (void) viewWillDisappear: (BOOL) animated {
			%orig;
			Frame *player = [%c(Frame) shared];
			if (!player.pauseInApps || !isInApp) {
				[player playHomescreen];
			}
		}

		- (void) viewDidDisappear: (BOOL) animated {
			%orig;
			isOnLockscreen = false;
			Frame *player = [%c(Frame) shared];
			// Pause if player's only enabled on lockscreen.
			[player pauseLockscreen];
			// Additonal check to prevent situations where a shared player is set
			// and when the user dismisses the cover sheet it doesn't stop playing.
			if (isInApp && player.pauseInApps)
				[player pauseSharedPlayer];		
		}

	%end

%end

void respringCallback(CFNotificationCenterRef center, void * observer, CFStringRef name, void const * object, CFDictionaryRef userInfo) {
	[[%c(FBSystemService) sharedInstance] exitAndRelaunch: true];
}

void videoChangedCallback(CFNotificationCenterRef center, void * observer, CFStringRef name, void const * object, CFDictionaryRef userInfo) {
	[Frame.shared reloadPlayers];
}

// Fix permissions for users who've updated Frame.
void createResourceFolder() {
	NSURL *frameFolder = [NSURL fileURLWithPath: @"/var/mobile/Documents/com.ZX02.Frame/"];

	// Create frame's folder.
	if (![NSFileManager.defaultManager fileExistsAtPath: frameFolder.path isDirectory: nil])
			if (![NSFileManager.defaultManager createDirectoryAtPath: frameFolder.path withIntermediateDirectories: YES attributes: nil error: nil])
					return;
  
	[NSFileManager.defaultManager setAttributes: @{ NSFilePosixPermissions: @511 } ofItemAtPath: frameFolder.path error: nil];
}

// Main
%ctor {
	// Create the resource folder if necessary & update permissions.
	createResourceFolder();

	%init(Tweak);

	if ([[[UIDevice currentDevice] systemVersion] floatValue] < 13.0) {
		%init(Fallback);
	}

	NSLog(@"[Frame]: Initialized %@", Frame.shared);

	// Listen for respring requests from pref.
	CFNotificationCenterRef center = CFNotificationCenterGetDarwinNotifyCenter();
	CFNotificationCenterAddObserver(center, nil, respringCallback, CFSTR("com.ZX02.framepreferences.respring"), nil, nil);
	CFNotificationCenterAddObserver(center, nil, videoChangedCallback, CFSTR("com.ZX02.framepreferences.videoChanged"), nil, nil);
}