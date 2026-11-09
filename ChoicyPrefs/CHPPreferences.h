extern NSArray *dylibsBeforeChoicy;
extern NSDictionary *preferences;
extern void choicy_reloadPreferences(void);
extern NSMutableDictionary *preferencesForWriting();
extern void writePreferences(NSMutableDictionary *mutablePrefs);
extern void presentNotLoadingFirstWarning(PSListController *plc, BOOL showDontShowAgainOption);
