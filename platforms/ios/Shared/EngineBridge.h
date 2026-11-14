#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
@interface JFCoreCandidate : NSObject
@property(nonatomic, readonly) NSString *reading;
@property(nonatomic, readonly) NSString *value;
@property(nonatomic, readonly) NSString *canonicalValue;
@end

@interface JFCoreEngine : NSObject
- (nullable instancetype)initWithResourceDirectory:(NSString *)path error:(NSError **)error;
@property(nonatomic, readonly) NSString *composition;
@property(nonatomic, readonly) NSString *phonetic;
@property(nonatomic, readonly) NSUInteger cursorUTF16;
@property(nonatomic) BOOL simplified;
@property(nonatomic) BOOL learningEnabled;
- (BOOL)key:(NSString *)key timestamp:(double)timestamp;
- (void)backspace;
- (void)cancel;
- (NSString *)commit;
- (void)moveCursor:(NSInteger)delta;
- (NSArray<JFCoreCandidate *> *)openCandidates;
- (NSArray<JFCoreCandidate *> *)openAssociations;
- (NSArray<NSString *> *)associationPrefix;
- (void)rankAssociations:(NSArray<NSNumber *> *)order;
- (BOOL)selectCandidate:(NSUInteger)index timestamp:(double)timestamp;
- (BOOL)selectAssociation:(NSUInteger)index timestamp:(double)timestamp;
- (NSData *)choiceSnapshot;
- (void)restoreChoices:(NSData *)data;
- (void)clearLearning;
- (void)reloadUserPhrases:(NSString *)included excluded:(NSString *)excluded;
- (BOOL)supportsReading:(NSString *)reading;
- (NSString *)suggestedReading:(NSString *)word;
- (NSString *)toSimplified:(NSString *)text;
- (NSString *)toTraditional:(NSString *)text;
@end
NS_ASSUME_NONNULL_END
