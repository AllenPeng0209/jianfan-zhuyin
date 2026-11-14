#include "OfflineStore.h"
#include "UTF8Helper.h"
#include "../Vendor/nlohmann/json.hpp"
#include <algorithm>
#include <chrono>
#include <cmath>
#include <fstream>
#include <map>
#include <numeric>
#include <set>
#include <sstream>
#include <stdexcept>
#include <thread>
#ifdef _WIN32
#include <windows.h>
#else
#include <fcntl.h>
#include <sys/file.h>
#include <sys/stat.h>
#include <unistd.h>
#endif

namespace Jianfan {
namespace {
using Json = nlohmann::json;
using Record = McBopomofo::UserOverrideModel::SnapshotRecord;
constexpr size_t limit = 4 * 1024 * 1024;

class FileLock {
 public:
  explicit FileLock(const std::filesystem::path& path) {
#ifdef _WIN32
    for (int attempt = 0; attempt < 100; ++attempt) {
      handle_ = CreateFileW(path.c_str(), GENERIC_READ | GENERIC_WRITE, 0, nullptr, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
      if (handle_ != INVALID_HANDLE_VALUE) { return; }
      if (GetLastError() != ERROR_SHARING_VIOLATION) { break; }
      std::this_thread::sleep_for(std::chrono::milliseconds(5));
    }
    throw std::runtime_error("Local data is unavailable or busy.");
#else
    fd_ = ::open(path.c_str(), O_RDWR | O_CREAT, 0600);
    if (fd_ < 0) { throw std::runtime_error("Cannot open local data lock."); }
    if (flock(fd_, LOCK_EX) != 0) { ::close(fd_); fd_ = -1; throw std::runtime_error("Cannot lock local data."); }
#endif
  }
  ~FileLock() {
#ifdef _WIN32
    if (handle_ != INVALID_HANDLE_VALUE) { CloseHandle(handle_); }
#else
    if (fd_ >= 0) { flock(fd_, LOCK_UN); ::close(fd_); }
#endif
  }
 private:
#ifdef _WIN32
  HANDLE handle_ = INVALID_HANDLE_VALUE;
#else
  int fd_ = -1;
#endif
};

std::string readFile(const std::filesystem::path& path) {
  if (std::filesystem::file_size(path) > limit) { throw std::runtime_error("Local file exceeds 4 MiB."); }
  std::ifstream file(path, std::ios::binary);
  if (!file) { throw std::runtime_error("Cannot read local data."); }
  return {std::istreambuf_iterator<char>(file), {}};
}

void privateFile(const std::filesystem::path& path) {
#ifndef _WIN32
  if (chmod(path.c_str(), 0600) != 0) { throw std::runtime_error("Cannot protect local file."); }
#else
  (void)path; // Inherit the current user's LocalAppData ACL; never broaden it.
#endif
}

void atomicWrite(const std::filesystem::path& path, const std::string& data, bool copyPrimary = true) {
  if (data.size() > limit) { throw std::runtime_error("Local data exceeds 4 MiB."); }
  auto temporary = path; temporary += ".tmp";
  auto backup = path; backup += ".bak";
  { std::ofstream file(temporary, std::ios::binary | std::ios::trunc);
    if (!file) { throw std::runtime_error("Cannot create local data."); }
    privateFile(temporary);
    if (!file.write(data.data(), static_cast<std::streamsize>(data.size())) || !file.flush()) {
      throw std::runtime_error("Cannot save local data.");
    }
  }
  privateFile(temporary);
  if (copyPrimary && std::filesystem::exists(path)) {
    std::filesystem::copy_file(path, backup, std::filesystem::copy_options::overwrite_existing);
    privateFile(backup);
  }
#ifdef _WIN32
  if (!MoveFileExW(temporary.c_str(), path.c_str(), MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH)) {
    throw std::runtime_error("Cannot replace local data.");
  }
#else
  std::filesystem::rename(temporary, path);
#endif
}

Json emptyLearning() { return {{"schemaVersion", 1}, {"overrides", Json::array()}, {"associations", Json::array()}}; }
bool validString(const Json& row, const char* key, size_t length) {
  return row.contains(key) && row[key].is_string() && !row[key].get_ref<const std::string&>().empty() &&
      row[key].get_ref<const std::string&>().size() <= length;
}
bool validCount(const Json& row) {
  return row.contains("count") && row["count"].is_number_unsigned() && row["count"].get<size_t>() > 0 &&
      row["count"].get<size_t>() <= 1000000 && row.contains("timestamp") && row["timestamp"].is_number() &&
      std::isfinite(row["timestamp"].get<double>()) && row["timestamp"].get<double>() >= 0;
}
Json decodeLearning(const std::string& data) {
  auto doc = Json::parse(data);
  if (!doc.is_object() || !doc.contains("schemaVersion") || !doc["schemaVersion"].is_number_integer()) {
    throw std::runtime_error("Invalid local data.");
  }
  if (doc["schemaVersion"] != 1) { throw std::domain_error("Local data requires a newer version."); }
  if (!doc.contains("overrides") || !doc["overrides"].is_array() || doc["overrides"].size() > 10000 ||
      !doc.contains("associations") || !doc["associations"].is_array() || doc["associations"].size() > 2000) {
    throw std::runtime_error("Invalid learning data.");
  }
  for (const auto& row : doc["overrides"]) {
    if (!validString(row,"key",4096) || !validString(row,"value",1024) || !validCount(row) ||
        !row.contains("forceHighScore") || !row["forceHighScore"].is_boolean()) { throw std::runtime_error("Invalid choice record."); }
  }
  for (const auto& row : doc["associations"]) {
    if (!validString(row,"prefixReading",1024) || !validString(row,"prefixValue",1024) ||
        !validString(row,"reading",1024) || !validString(row,"value",1024) || !validCount(row)) {
      throw std::runtime_error("Invalid association record.");
    }
  }
  return doc;
}
std::vector<Record> records(const Json& doc) {
  std::vector<Record> result;
  for (const auto& row : doc["overrides"]) {
    result.push_back({row["key"],row["value"],row["count"],row["timestamp"],row["forceHighScore"]});
  }
  return result;
}
bool same(const Json& row, const AssociationPrefix& prefix, const Candidate& candidate) {
  return row["prefixReading"] == prefix.reading && row["prefixValue"] == prefix.value &&
      row["reading"] == candidate.reading && row["value"] == candidate.canonicalValue;
}
bool validPhrase(const UserPhrase& row, const std::function<bool(const std::string&)>& validate) {
  auto noSpace = [](const std::string& value) {
    return !value.empty() && value.find_first_of(" \t\r\n\v\f") == std::string::npos &&
        std::none_of(value.begin(),value.end(),[](unsigned char c) { return c < 32 || c == 127; });
  };
  return noSpace(row.phrase) && row.phrase[0] != '#' && McBopomofo::CodePointCount(row.phrase) <= 80 &&
      row.phrase.size() <= 320 && noSpace(row.reading) && row.reading.size() <= 256 && validate(row.reading);
}
}

struct OfflineStore::Impl {
  std::filesystem::path directory;
  mutable std::string error;
  std::vector<Record> baseline;
  explicit Impl(std::filesystem::path value) : directory(std::move(value)) {}
  FileLock lock() const {
    std::filesystem::create_directories(directory);
    return FileLock(directory / "data.lock");
  }
  std::pair<Json,bool> load() const {
    auto path = directory / "learning-v1.json";
    if (!std::filesystem::exists(path)) { return {emptyLearning(), false}; }
    try { return {decodeLearning(readFile(path)), true}; }
    catch (const std::domain_error&) { throw; }
    catch (const std::exception&) {
      auto backup = path; backup += ".bak";
      return {decodeLearning(readFile(backup)), false};
    }
  }
  void write(Json& doc, bool primaryValid, bool resetBackup = false) const {
    auto path = directory / "learning-v1.json";
    auto data = doc.dump();
    atomicWrite(path, data, primaryValid);
    if (resetBackup) { auto backup = path; backup += ".bak"; atomicWrite(backup, data, false); }
  }
  template<class F> bool attempt(F action) const {
    try { auto guard = lock(); action(); error.clear(); return true; }
    catch (const std::exception& e) { error = e.what(); return false; }
  }
  std::vector<std::string> lines() const {
    auto path = directory / "user-phrases.txt";
    std::vector<std::string> result;
    if (!std::filesystem::exists(path)) { return result; }
    std::istringstream stream(readFile(path));
    std::string line;
    while (std::getline(stream,line)) { if (!line.empty() && line.back() == '\r') { line.pop_back(); } result.push_back(line); }
    return result;
  }
  static UserPhrase phrase(const std::string& line) {
    std::istringstream stream(line);
    UserPhrase row;
    stream >> row.phrase >> row.reading;
    if (row.phrase.empty() || row.phrase[0] == '#' || row.reading.empty()) { return {}; }
    return row;
  }
  void mergePhrases(const std::vector<UserPhrase>& entries) const {
    auto content = lines();
    for (const auto& entry : entries) {
      auto found = std::find_if(content.begin(),content.end(),[&](const auto& line) {
        auto existing = phrase(line); return existing.phrase == entry.phrase && existing.reading == entry.reading;
      });
      if (found == content.end()) { content.push_back(entry.phrase + " " + entry.reading); }
    }
    std::string text;
    for (const auto& line : content) { text += line + "\n"; }
    atomicWrite(directory / "user-phrases.txt", text);
  }
};

OfflineStore::OfflineStore(std::filesystem::path directory) : impl_(std::make_shared<Impl>(std::move(directory))) {}
std::vector<Record> OfflineStore::choices() {
  std::vector<Record> result;
  impl_->attempt([&] { result = records(impl_->load().first); impl_->baseline = result; });
  return result;
}
bool OfflineStore::saveChoices(const std::vector<Record>& snapshot) {
  return impl_->attempt([&] {
    auto [doc, valid] = impl_->load();
    auto& rows = doc["overrides"];
    for (const auto& record : snapshot) {
      auto previous = std::find_if(impl_->baseline.begin(),impl_->baseline.end(),[&](const auto& row) {
        return row.key == record.key && row.candidate == record.candidate;
      });
      size_t priorCount = previous == impl_->baseline.end() ? 0 : previous->count;
      if (record.count <= priorCount) { continue; }
      auto existing = std::find_if(rows.begin(),rows.end(),[&](const Json& row) { return row["key"] == record.key && row["value"] == record.candidate; });
      size_t count = record.count - priorCount;
      if (existing != rows.end()) { count += (*existing)["count"].get<size_t>(); }
      Json updated{{"key",record.key},{"value",record.candidate},{"count",std::min(count,size_t(1000000))},
                   {"timestamp",record.timestamp},{"forceHighScore",record.forceHighScore}};
      if (existing == rows.end()) { rows.push_back(updated); }
      else if (record.timestamp >= (*existing)["timestamp"].get<double>()) { *existing = updated; }
      else { (*existing)["count"] = updated["count"]; }
    }
    std::stable_sort(rows.begin(),rows.end(),[](const Json& a, const Json& b) { return a["timestamp"] > b["timestamp"]; });
    if (rows.size() > 10000) { rows.erase(rows.begin() + 10000, rows.end()); }
    decodeLearning(doc.dump());
    impl_->write(doc, valid);
    impl_->baseline = snapshot;
  });
}
bool OfflineStore::recordAssociation(const AssociationPrefix& prefix, const Candidate& candidate, double timestamp) {
  return impl_->attempt([&] {
    auto [doc, valid] = impl_->load();
    auto& rows = doc["associations"];
    auto row = std::find_if(rows.begin(),rows.end(),[&](const Json& r) { return same(r,prefix,candidate); });
    Json updated{{"prefixReading",prefix.reading},{"prefixValue",prefix.value},{"reading",candidate.reading},
                 {"value",candidate.canonicalValue},{"count",1u},{"timestamp",timestamp}};
    if (row == rows.end()) { rows.push_back(updated); }
    else { updated["count"] = std::min((*row)["count"].get<size_t>() + 1, size_t(1000000)); *row = updated; }
    std::stable_sort(rows.begin(),rows.end(),[](const Json& a, const Json& b) { return a["timestamp"] > b["timestamp"]; });
    if (rows.size() > 2000) { rows.erase(rows.begin() + 2000,rows.end()); }
    decodeLearning(doc.dump());
    impl_->write(doc, valid);
  });
}
std::vector<size_t> OfflineStore::rankAssociations(const AssociationPrefix& prefix, const std::vector<Candidate>& candidates, double timestamp) {
  std::vector<size_t> order(candidates.size()); std::iota(order.begin(),order.end(),0);
  impl_->attempt([&] {
    auto rows = impl_->load().first["associations"];
    std::vector<double> scores(candidates.size(),0);
    for (size_t i = 0; i < candidates.size(); ++i) {
      auto row = std::find_if(rows.begin(),rows.end(),[&](const Json& r) { return same(r,prefix,candidates[i]); });
      if (row != rows.end()) { scores[i] = (*row)["count"].get<double>() * std::exp2(-std::max(0.,timestamp - (*row)["timestamp"].get<double>()) / (30 * 86400)); }
    }
    std::stable_sort(order.begin(),order.end(),[&](size_t a, size_t b) { return scores[a] > scores[b]; });
  });
  return order;
}
bool OfflineStore::clearLearning() {
  return impl_->attempt([&] { auto loaded = impl_->load(); auto doc = emptyLearning(); impl_->write(doc,loaded.second,true); impl_->baseline.clear(); });
}
std::vector<UserPhrase> OfflineStore::phrases() const {
  std::vector<UserPhrase> result;
  impl_->attempt([&] {
    for (const auto& line : impl_->lines()) { auto row = Impl::phrase(line); if (!row.phrase.empty()) { result.push_back(row); } }
  });
  return result;
}
bool OfflineStore::upsertPhrase(const UserPhrase& phrase, const std::function<bool(const std::string&)>& validateReading) {
  return impl_->attempt([&] { if (!validPhrase(phrase,validateReading)) { throw std::runtime_error("Invalid phrase or reading."); } impl_->mergePhrases({phrase}); });
}
bool OfflineStore::removePhrase(const UserPhrase& phrase) {
  return impl_->attempt([&] {
    std::string content;
    for (const auto& line : impl_->lines()) {
      auto row = Impl::phrase(line);
      if (row.phrase != phrase.phrase || row.reading != phrase.reading) { content += line + "\n"; }
    }
    atomicWrite(phrasesPath(),content);
  });
}
bool OfflineStore::importPhrases(const std::string& json, const std::function<bool(const std::string&)>& validateReading) {
  return impl_->attempt([&] {
    if (json.size() > limit) { throw std::runtime_error("Import exceeds 4 MiB."); }
    auto doc = Json::parse(json);
    if (!doc.is_object() || doc.value("schemaVersion",0) != 1 || !doc.contains("entries") || !doc["entries"].is_array() || doc["entries"].size() > 10000) { throw std::runtime_error("Invalid lexicon format."); }
    std::vector<UserPhrase> rows;
    for (const auto& entry : doc["entries"]) {
      if (!entry.is_object() || !entry.contains("phrase") || !entry["phrase"].is_string() || !entry.contains("reading") || !entry["reading"].is_string()) { throw std::runtime_error("Invalid lexicon entry."); }
      UserPhrase row{entry["phrase"],entry["reading"]};
      if (!validPhrase(row,validateReading)) { throw std::runtime_error("Invalid phrase or reading."); }
      rows.push_back(row);
    }
    impl_->mergePhrases(rows);
  });
}
std::string OfflineStore::exportPhrases() const {
  Json doc{{"schemaVersion",1},{"entries",Json::array()}};
  for (const auto& row : phrases()) { doc["entries"].push_back({{"phrase",row.phrase},{"reading",row.reading}}); }
  return doc.dump(2);
}
std::filesystem::path OfflineStore::phrasesPath() const { return impl_->directory / "user-phrases.txt"; }
std::string OfflineStore::error() const { return impl_->error; }
}
