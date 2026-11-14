#import "EngineBridge.h"
#include "Session.h"

@interface JFCoreCandidate ()
- (instancetype)initWithCandidate:(const Jianfan::Candidate&)candidate;
@end
@implementation JFCoreCandidate
- (instancetype)initWithCandidate:(const Jianfan::Candidate&)candidate {
    if ((self = [super init])) {
        _reading = @(candidate.reading.c_str());
        _value = @(candidate.value.c_str());
        _canonicalValue = @(candidate.canonicalValue.c_str());
    }
    return self;
}
@end

@implementation JFCoreEngine {
    std::unique_ptr<Jianfan::Session> _session;
}
- (instancetype)initWithResourceDirectory:(NSString *)path error:(NSError **)error {
    if (!(self = [super init])) { return nil; }
    try {
        auto file = [&](NSString *name) { return std::string([path stringByAppendingPathComponent:name].UTF8String); };
        _session = std::make_unique<Jianfan::Session>(Jianfan::Config{
            file(@"data.txt"),file(@"associated-phrases-v2.txt"),std::string(path.UTF8String),"","",true});
        if (!_session->ready()) { throw std::runtime_error("Bundled dictionary is unavailable."); }
        _simplified = YES; _learningEnabled = YES;
        return self;
    } catch (const std::exception& exception) {
        if (error) { *error = [NSError errorWithDomain:@"Jianfan.Core" code:1 userInfo:@{NSLocalizedDescriptionKey:@(exception.what())}]; }
        return nil;
    }
}
- (NSString *)composition { return @(_session->composition().c_str()); }
- (NSString *)phonetic { return @(_session->phonetic().c_str()); }
- (NSUInteger)cursorUTF16 { return _session->cursorUtf16(); }
- (void)setSimplified:(BOOL)enabled { _simplified = enabled; _session->setSimplified(enabled); }
- (void)setLearningEnabled:(BOOL)enabled { _learningEnabled = enabled; _session->setLearningEnabled(enabled); }
- (BOOL)key:(NSString *)key timestamp:(double)timestamp {
    return key.length == 1 && [key canBeConvertedToEncoding:NSASCIIStringEncoding] && _session->key(*key.UTF8String,timestamp);
}
- (void)backspace { _session->backspace(); }
- (void)cancel { _session->cancel(); }
- (NSString *)commit { return @(_session->commit().c_str()); }
- (void)moveCursor:(NSInteger)delta { _session->moveCursor(static_cast<int>(delta)); }
- (NSArray<JFCoreCandidate *> *)converted:(const std::vector<Jianfan::Candidate>&)candidates {
    NSMutableArray *result = [NSMutableArray arrayWithCapacity:candidates.size()];
    for (const auto& candidate : candidates) { [result addObject:[[JFCoreCandidate alloc] initWithCandidate:candidate]]; }
    return result;
}
- (NSArray<JFCoreCandidate *> *)openCandidates { _session->openCandidates(); return [self converted:_session->candidates()]; }
- (NSArray<JFCoreCandidate *> *)openAssociations { _session->openAssociations(); return [self converted:_session->associations()]; }
- (NSArray<NSString *> *)associationPrefix { auto prefix = _session->associationPrefix(); return @[@(prefix.reading.c_str()),@(prefix.value.c_str())]; }
- (void)rankAssociations:(NSArray<NSNumber *> *)order {
    std::vector<size_t> indices; for (NSNumber *index in order) { indices.push_back(index.unsignedIntegerValue); }
    _session->rankAssociations(indices);
}
- (BOOL)selectCandidate:(NSUInteger)index timestamp:(double)timestamp { return _session->selectCandidate(index,timestamp); }
- (BOOL)selectAssociation:(NSUInteger)index timestamp:(double)timestamp { return _session->selectAssociation(index,timestamp); }
- (NSData *)choiceSnapshot {
    NSMutableArray *rows = [NSMutableArray array];
    for (const auto& record : _session->learnedChoices()) {
        [rows addObject:@{@"key":@(record.key.c_str()),@"value":@(record.candidate.c_str()),@"count":@(record.count),
                          @"timestamp":@(record.timestamp),@"forceHighScore":@(record.forceHighScore)}];
    }
    return [NSJSONSerialization dataWithJSONObject:rows options:0 error:nil] ?: [NSData data];
}
- (void)restoreChoices:(NSData *)data {
    if (data.length > 4 * 1024 * 1024) { return; }
    id rows = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![rows isKindOfClass:[NSArray class]] || [rows count] > 10000) { return; }
    std::vector<McBopomofo::UserOverrideModel::SnapshotRecord> records;
    for (id row in rows) {
        if (![row isKindOfClass:[NSDictionary class]]) { return; }
        NSString *key = row[@"key"], *value = row[@"value"];
        NSNumber *count = row[@"count"], *timestamp = row[@"timestamp"], *force = row[@"forceHighScore"];
        if (![key isKindOfClass:NSString.class] || ![value isKindOfClass:NSString.class] ||
            ![count isKindOfClass:NSNumber.class] || ![timestamp isKindOfClass:NSNumber.class] || ![force isKindOfClass:NSNumber.class]) { return; }
        records.push_back({key.UTF8String,value.UTF8String,count.unsignedIntegerValue,timestamp.doubleValue,force.boolValue});
    }
    _session->restoreChoices(records);
}
- (void)clearLearning { _session->clearLearning(); }
- (void)reloadUserPhrases:(NSString *)included excluded:(NSString *)excluded { _session->reloadUserPhrases(included.UTF8String,excluded.UTF8String); }
- (BOOL)supportsReading:(NSString *)reading { return _session->supportsReading(reading.UTF8String); }
- (NSString *)suggestedReading:(NSString *)word { return @(_session->suggestedReading(word.UTF8String).c_str()); }
- (NSString *)toSimplified:(NSString *)text { return @(_session->toSimplified(text.UTF8String).c_str()); }
- (NSString *)toTraditional:(NSString *)text { return @(_session->toTraditional(text.UTF8String).c_str()); }
@end
