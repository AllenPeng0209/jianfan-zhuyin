#pragma once
#include <memory>
#include <string>
#include <vector>
#include "UserOverrideModel.h"

namespace Jianfan {
struct Candidate { std::string reading; std::string value; std::string canonicalValue; };
struct AssociationPrefix { std::string reading; std::string value; };
struct Config {
  std::string modelPath;
  std::string associationsPath;
  std::string conversionDirectory;
  std::string userPhrasesPath;
  std::string excludedPhrasesPath;
  bool simplified = true;
};

class Session {
 public:
  explicit Session(Config config);
  ~Session();
  Session(const Session&) = delete;
  Session& operator=(const Session&) = delete;
  bool ready() const;
  bool key(char ascii, double timestamp);
  void backspace();
  void cancel();
  void moveCursor(int delta);
  std::string commit();
  std::string composition() const;
  std::string phonetic() const;
  size_t cursorUtf16() const;
  void setSimplified(bool enabled);
  void setLearningEnabled(bool enabled);
  void openCandidates();
  bool selectCandidate(size_t index, double timestamp);
  const std::vector<Candidate>& candidates() const;
  void openAssociations();
  const std::vector<Candidate>& associations() const;
  AssociationPrefix associationPrefix() const;
  void rankAssociations(const std::vector<size_t>& order);
  bool selectAssociation(size_t index, double timestamp);
  std::vector<McBopomofo::UserOverrideModel::SnapshotRecord> learnedChoices() const;
  void restoreChoices(const std::vector<McBopomofo::UserOverrideModel::SnapshotRecord>& records);
  void clearLearning();
  void reloadUserPhrases(const std::string& included, const std::string& excluded);
  bool supportsReading(const std::string& reading) const;
  std::string suggestedReading(const std::string& word) const;
  std::string toSimplified(const std::string& text) const;
  std::string toTraditional(const std::string& text) const;
 private:
  struct Impl;
  std::unique_ptr<Impl> impl_;
};
}
