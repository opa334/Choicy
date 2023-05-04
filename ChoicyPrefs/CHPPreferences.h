extern NSArray *dylibsBeforeChoicy;
extern NSDictionary *preferences;
extern NSMutableDictionary *preferencesForWriting();
extern void writePreferences(NSMutableDictionary *mutablePrefs);
extern void presentNotLoadingFirstWarning(PSListController *plc, BOOL showDontShowAgainOption);