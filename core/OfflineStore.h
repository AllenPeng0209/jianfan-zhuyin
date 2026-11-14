#pragma once
#include <filesystem>
#include <functional>
#include <optional>
#include <string>
#include <vector>
#include "Session.h"

namespace Jianfan {
struct UserPhrase { std::string phrase; std::string reading; };
class OfflineStore {
 public:
  explicit OfflineStore(std::filesystem::path directory);
  std::vector<McBopomofo::UserOverrideModel::SnapshotRecord> choices();
  bool saveChoices(const std::vector<McBopomofo::UserOverrideModel::SnapshotRecord>& snapshot);
  bool recordAssociation(const AssociationPrefix& prefix, const Candidate& candidate, double timestamp);
  std::vector<size_t> rankAssociations(const AssociationPrefix& prefix, const std::vector<Candidate>& candidates, double timestamp);
  bool clearLearning();
  std::vector<UserPhrase> phrases() const;
  bool upsertPhrase(const UserPhrase& phrase, const std::function<bool(const std::string&)>& validateReading,
                    const std::optional<UserPhrase>& original = std::nullopt);
  bool removePhrase(const UserPhrase& phrase);
  bool importPhrases(const std::string& json, const std::function<bool(const std::string&)>& validateReading);
  std::string exportPhrases() const;
  std::filesystem::path phrasesPath() const;
  std::string error() const;
 private:
  struct Impl;
  std::shared_ptr<Impl> impl_;
};
}
