#include "Session.h"

#include <algorithm>
#include <filesystem>
#include <list>
#include <unordered_set>

#include "McBopomofoLM.h"
#include "UTF8Helper.h"
#include "Mandarin/Mandarin.h"
#include "Converter.hpp"
#include "Conversion.hpp"
#include "ConversionChain.hpp"
#include "DictGroup.hpp"
#include "MarisaDict.hpp"
#include "MaxMatchSegmentation.hpp"

namespace Jianfan {
namespace {
using Grid = Formosa::Gramambular2::ReadingGrid;
using Mandarin = Formosa::Mandarin::BopomofoSyllable;
using Phrases = McBopomofo::AssociatedPhrasesV2;

std::shared_ptr<opencc::Converter> converter(const std::string& directory, const std::string& prefix) {
  auto load = [&](const std::string& name) {
    return opencc::SerializableDict::NewFromFile<opencc::MarisaDict>(
        (std::filesystem::u8path(directory) / name).string());
  };
  auto dict = std::make_shared<opencc::DictGroup>(std::list<opencc::DictPtr>{
      load(prefix + "Phrases.ocd2"), load(prefix + "Characters.ocd2")});
  auto segmentation = std::make_shared<opencc::MaxMatchSegmentation>(dict);
  auto chain = std::make_shared<opencc::ConversionChain>(
      std::list<opencc::ConversionPtr>{std::make_shared<opencc::Conversion>(dict)});
  return std::make_shared<opencc::Converter>(prefix, segmentation, chain);
}

size_t utf16Length(const std::string& value) {
  size_t length = 0;
  for (const auto& cp : McBopomofo::Split(value)) { length += cp.size() == 4 ? 2 : 1; }
  return length;
}
}

struct Session::Impl {
  std::shared_ptr<McBopomofo::McBopomofoLM> model = std::make_shared<McBopomofo::McBopomofoLM>();
  Grid grid{model};
  Grid::WalkResult walk;
  Formosa::Mandarin::BopomofoReadingBuffer buffer{Formosa::Mandarin::BopomofoKeyboardLayout::StandardLayout()};
  McBopomofo::UserOverrideModel memory{5000, 30 * 86400};
  std::shared_ptr<opencc::Converter> t2s, s2t;
  std::vector<Candidate> candidates, associations;
  AssociationPrefix prefix;
  size_t prefixLength = 0;
  bool simplified, learning = true;

  explicit Impl(Config config) : simplified(config.simplified) {
    model->loadLanguageModel(config.modelPath.c_str());
    model->loadAssociatedPhrasesV2(config.associationsPath.c_str());
    model->loadUserPhrases(config.userPhrasesPath.empty() ? nullptr : config.userPhrasesPath.c_str(),
                           config.excludedPhrasesPath.empty() ? nullptr : config.excludedPhrasesPath.c_str());
    t2s = converter(config.conversionDirectory, "TS");
    s2t = converter(config.conversionDirectory, "ST");
  }
  std::string display(const std::string& value) const { return simplified ? t2s->Convert(value) : value; }
  size_t actualCursor() const { return grid.cursor() > 0 ? grid.cursor() - 1 : 0; }
  void closeMenus() { candidates.clear(); associations.clear(); prefix = {}; prefixLength = 0; }
  void update() { walk = grid.walk(); }
  std::pair<std::string, std::string> splitComposition() const {
    std::string before, after;
    size_t position = 0;
    for (const auto& node : walk.nodes) {
      auto characters = McBopomofo::Split(node->value());
      size_t count = node->spanningLength();
      size_t split = grid.cursor() <= position ? 0 : std::min(grid.cursor() - position, count);
      // A user alias may contain more characters than its reading span.
      size_t splitCharacters = split == count ? characters.size() : std::min(split, characters.size());
      for (size_t i = 0; i < characters.size(); ++i) {
        (i < splitCharacters ? before : after) += characters[i];
      }
      position += count;
    }
    return {before, after};
  }
};

Session::Session(Config config) : impl_(std::make_unique<Impl>(std::move(config))) {}
Session::~Session() = default;
bool Session::ready() const { return impl_->model->isDataModelLoaded() && impl_->model->isAssociatedPhrasesV2Loaded(); }

bool Session::key(char ascii, double timestamp) {
  auto& p = *impl_;
  bool valid = p.buffer.isValidKey(ascii);
  if (!valid && !(ascii == ' ' && !p.buffer.isEmpty())) { return false; }
  p.closeMenus();
  if (valid) { p.buffer.combineKey(ascii); }
  if ((p.buffer.hasToneMarker() && !p.buffer.hasToneMarkerOnly()) || ascii == ' ') {
    std::string reading = p.buffer.composedString();
    if (p.model->hasUnigrams(reading) && p.grid.insertReading(reading)) {
      p.buffer.clear();
      p.update();
      if (p.learning) {
        auto suggestion = p.memory.suggest(p.walk, p.actualCursor(), timestamp);
        if (!suggestion.empty()) {
          auto type = suggestion.forceHighScoreOverride ? Grid::Node::OverrideType::kOverrideValueWithHighScore :
              Grid::Node::OverrideType::kOverrideValueWithScoreFromTopUnigram;
          p.grid.overrideCandidate(p.actualCursor(), suggestion.candidate, type);
          p.update();
        }
      }
    }
  }
  return true;
}

void Session::backspace() {
  auto& p = *impl_;
  p.closeMenus();
  if (!p.buffer.isEmpty()) { p.buffer.backspace(); }
  else { p.grid.deleteReadingBeforeCursor(); p.update(); }
}
void Session::cancel() {
  if (!impl_->candidates.empty() || !impl_->associations.empty()) { impl_->closeMenus(); }
  else if (!impl_->buffer.isEmpty()) { impl_->buffer.clear(); }
  else { impl_->grid.clear(); impl_->update(); }
}
void Session::moveCursor(int delta) {
  auto& p = *impl_;
  if (!p.buffer.isEmpty()) { return; }
  p.closeMenus();
  auto cursor = std::clamp(static_cast<long long>(p.grid.cursor()) + delta, 0LL, static_cast<long long>(p.grid.length()));
  p.grid.setCursor(static_cast<size_t>(cursor));
}
std::string Session::commit() {
  std::string output = composition();
  impl_->buffer.clear(); impl_->grid.clear(); impl_->update(); impl_->closeMenus();
  return output;
}
std::string Session::composition() const {
  auto [before, after] = impl_->splitComposition();
  return impl_->display(before + impl_->buffer.composedString() + after);
}
std::string Session::phonetic() const { return impl_->buffer.composedString(); }
size_t Session::cursorUtf16() const {
  auto [before, after] = impl_->splitComposition();
  return utf16Length(impl_->display(before + impl_->buffer.composedString()));
}
void Session::setSimplified(bool enabled) { impl_->simplified = enabled; impl_->closeMenus(); }
void Session::setLearningEnabled(bool enabled) { impl_->learning = enabled; }
void Session::openCandidates() {
  auto& p = *impl_;
  p.closeMenus();
  if (!p.buffer.isEmpty()) { return; }
  std::unordered_set<std::string> seen;
  for (const auto& candidate : p.grid.candidatesAt(p.actualCursor())) {
    auto value = p.display(candidate.value);
    if (seen.insert(value).second) { p.candidates.push_back({candidate.reading, value, candidate.value}); }
  }
}
bool Session::selectCandidate(size_t index, double timestamp) {
  auto& p = *impl_;
  if (index >= p.candidates.size()) { return false; }
  auto candidate = p.candidates[index];
  auto before = p.walk.copyWithFixedNodes();
  if (!p.grid.overrideCandidate(p.actualCursor(), Grid::Candidate(candidate.reading, candidate.canonicalValue))) { return false; }
  p.update();
  if (p.learning) { p.memory.observe(before, p.walk, p.actualCursor(), timestamp); }
  p.closeMenus();
  return true;
}
const std::vector<Candidate>& Session::candidates() const { return impl_->candidates; }
void Session::openAssociations() {
  auto& p = *impl_;
  p.closeMenus();
  if (!p.buffer.isEmpty() || p.grid.cursor() != p.grid.length()) { return; }
  std::vector<std::string> readings;
  std::string prefix;
  for (auto it = p.walk.nodes.rbegin(); it != p.walk.nodes.rend(); ++it) {
    prefix = (*it)->value() + prefix;
    auto components = Phrases::SplitReadings((*it)->reading());
    readings.insert(readings.begin(), components.begin(), components.end());
    if (readings.size() > Grid::kMaximumSpanLength) { break; }
    auto found = p.model->findAssociatedPhrasesV2(prefix, readings);
    if (found.empty()) { continue; }
    std::vector<Candidate> next;
    for (const auto& phrase : found) {
      if (phrase.readings.size() <= Grid::kMaximumSpanLength && phrase.readings.size() > readings.size()) {
        next.push_back({phrase.combinedReading(), p.display(phrase.value), phrase.value});
      }
    }
    if (!next.empty()) {
      p.associations = std::move(next);
      p.prefix = {Phrases::CombineReadings(readings), prefix};
      p.prefixLength = readings.size();
    }
  }
}
const std::vector<Candidate>& Session::associations() const { return impl_->associations; }
AssociationPrefix Session::associationPrefix() const { return impl_->prefix; }
void Session::rankAssociations(const std::vector<size_t>& order) {
  if (order.size() != impl_->associations.size()) { return; }
  std::vector<Candidate> ranked;
  std::unordered_set<size_t> seen;
  for (size_t i : order) {
    if (i >= order.size() || !seen.insert(i).second) { return; }
    ranked.push_back(impl_->associations[i]);
  }
  impl_->associations = std::move(ranked);
}
bool Session::selectAssociation(size_t index, double timestamp) {
  auto& p = *impl_;
  if (index >= p.associations.size()) { return false; }
  auto candidate = p.associations[index];
  auto readings = Phrases::SplitReadings(candidate.reading);
  for (size_t i = p.prefixLength; i < readings.size(); ++i) {
    if (!p.grid.insertReading(readings[i])) { return false; }
  }
  p.update();
  auto before = p.walk.copyWithFixedNodes();
  bool result = p.grid.overrideCandidate(p.actualCursor(), Grid::Candidate(candidate.reading, candidate.canonicalValue));
  p.update();
  if (result && p.learning) { p.memory.observe(before, p.walk, p.actualCursor(), timestamp); }
  p.closeMenus();
  return result;
}
std::vector<McBopomofo::UserOverrideModel::SnapshotRecord> Session::learnedChoices() const { return impl_->memory.exportRecords(); }
void Session::restoreChoices(const std::vector<McBopomofo::UserOverrideModel::SnapshotRecord>& records) { impl_->memory.importRecords(records); }
void Session::clearLearning() { impl_->memory.clear(); }
void Session::reloadUserPhrases(const std::string& included, const std::string& excluded) {
  impl_->model->loadUserPhrases(included.c_str(), excluded.c_str()); impl_->closeMenus();
}
bool Session::supportsReading(const std::string& reading) const {
  auto components = Phrases::SplitReadings(reading);
  if (components.empty() || components.size() > Grid::kMaximumSpanLength) { return false; }
  for (const auto& component : components) {
    auto syllable = Mandarin::FromComposedString(component);
    if (component.empty() || syllable.composedString() != component || !impl_->model->hasUnigrams(component)) { return false; }
  }
  return true;
}
std::string Session::suggestedReading(const std::string& word) const {
  std::string canonical = toTraditional(word);
  auto reading = impl_->model->getReading(canonical);
  if (!reading.empty()) { return supportsReading(reading) ? reading : ""; }
  std::vector<std::string> components;
  for (const auto& cp : McBopomofo::Split(canonical)) {
    auto component = impl_->model->getReading(cp);
    if (component.empty()) { return {}; }
    components.push_back(component);
  }
  reading = Phrases::CombineReadings(components);
  return supportsReading(reading) ? reading : "";
}
std::string Session::toSimplified(const std::string& text) const { return impl_->t2s->Convert(text); }
std::string Session::toTraditional(const std::string& text) const { return impl_->s2t->Convert(text); }
}
