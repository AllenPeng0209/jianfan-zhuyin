#include "OfflineStore.h"
#include "gtest/gtest.h"
#include <chrono>
#include <fstream>

namespace {
class StoreTest : public testing::Test {
 protected:
  std::filesystem::path directory;
  void SetUp() override {
    directory = std::filesystem::temp_directory_path() / std::filesystem::u8path("jianfan-離線-" +
      std::to_string(std::chrono::steady_clock::now().time_since_epoch().count()));
    std::filesystem::create_directories(directory);
  }
  void TearDown() override { std::filesystem::remove_all(directory); }
};
bool reading(const std::string& value) { return value == "ㄒㄧㄥ-ㄏㄜˊ" || value == "ㄋㄧˇ-ㄏㄠˇ"; }
}

TEST_F(StoreTest, ChoicesSurviveRestartAndConcurrentHostsMergeNewSelections) {
  Jianfan::OfflineStore first(directory), second(directory);
  EXPECT_TRUE(first.choices().empty());
  EXPECT_TRUE(second.choices().empty());
  ASSERT_TRUE(first.saveChoices({{"context", "紀", 2, 1000, true}}));
  ASSERT_TRUE(second.saveChoices({{"other", "記", 1, 1001, false}}));
  ASSERT_TRUE(first.saveChoices({{"context", "紀", 3, 1002, true}}));
  Jianfan::OfflineStore restarted(directory);
  auto rows = restarted.choices();
  ASSERT_EQ(rows.size(), 2);
  auto found = std::find_if(rows.begin(), rows.end(), [](const auto& row) { return row.candidate == "紀"; });
  ASSERT_NE(found, rows.end());
  EXPECT_EQ(found->count, 3);
}

TEST_F(StoreTest, FrequentlyChosenAssociationsRiseAndTiesKeepBaseOrder) {
  Jianfan::OfflineStore store(directory);
  std::vector<Jianfan::Candidate> candidates{{"a-b", "中華", "中華"}, {"a-c", "中國", "中國"}, {"a-d", "中央", "中央"}};
  Jianfan::AssociationPrefix prefix{"a", "中"};
  EXPECT_EQ(store.rankAssociations(prefix, candidates, 1000), (std::vector<size_t>{0,1,2}));
  ASSERT_TRUE(store.recordAssociation(prefix, candidates[2], 1000));
  Jianfan::OfflineStore restarted(directory);
  EXPECT_EQ(restarted.rankAssociations(prefix, candidates, 1001), (std::vector<size_t>{2,0,1}));
  ASSERT_TRUE(restarted.clearLearning());
  EXPECT_EQ(restarted.rankAssociations(prefix, candidates, 1002), (std::vector<size_t>{0,1,2}));
  Jianfan::OfflineStore afterClear(directory);
  EXPECT_TRUE(afterClear.choices().empty());
}

TEST_F(StoreTest, LexiconInterchangeValidatesWholeImportAndPreservesOtherEdits) {
  Jianfan::OfflineStore a(directory), b(directory);
  ASSERT_TRUE(a.upsertPhrase({"星禾", "ㄒㄧㄥ-ㄏㄜˊ"}, reading));
  ASSERT_TRUE(b.upsertPhrase({"你好", "ㄋㄧˇ-ㄏㄠˇ"}, reading));
  EXPECT_EQ(a.phrases().size(), 2);
  EXPECT_FALSE(a.importPhrases(R"({"schemaVersion":1,"entries":[{"phrase":"A","reading":"ㄋㄧˇ-ㄏㄠˇ"},{"phrase":"B","reading":"invalid"}]})", reading));
  EXPECT_EQ(a.phrases().size(), 2);
  auto exported = a.exportPhrases();
  ASSERT_TRUE(a.removePhrase({"星禾", "ㄒㄧㄥ-ㄏㄜˊ"}));
  EXPECT_EQ(a.phrases().size(), 1);
  ASSERT_TRUE(a.importPhrases(exported, reading));
  EXPECT_EQ(a.phrases().size(), 2);
  EXPECT_TRUE(std::filesystem::exists(a.phrasesPath()));
}

TEST_F(StoreTest, FutureSchemasRemainUntouchedAndCorruptionRecoversBackup) {
  Jianfan::OfflineStore store(directory);
  ASSERT_TRUE(store.saveChoices({{"k", "紀", 1, 1000, false}}));
  ASSERT_TRUE(store.saveChoices({{"k", "紀", 2, 1001, false}}));
  auto path = directory / "learning-v1.json";
  { std::ofstream file(path); file << "broken"; }
  Jianfan::OfflineStore recovered(directory);
  ASSERT_EQ(recovered.choices().size(), 1);
  EXPECT_EQ(recovered.choices()[0].count, 1);
  { std::ofstream file(path); file << R"({"schemaVersion":99})"; }
  Jianfan::OfflineStore future(directory);
  EXPECT_FALSE(future.clearLearning());
  std::ifstream file(path); std::string data((std::istreambuf_iterator<char>(file)), {});
  EXPECT_EQ(data, R"({"schemaVersion":99})");
}

TEST_F(StoreTest, EditingAWordPreservesCommentsAndRejectsAStaleOriginal) {
  Jianfan::OfflineStore store(directory);
  { std::ofstream file(store.phrasesPath()); file << "# custom note\n星禾 ㄒㄧㄥ-ㄏㄜˊ -2\n"; }
  Jianfan::UserPhrase original{"星禾","ㄒㄧㄥ-ㄏㄜˊ"};
  ASSERT_TRUE(store.upsertPhrase({"星和","ㄋㄧˇ-ㄏㄠˇ"},reading,original));
  auto rows = store.phrases();
  ASSERT_EQ(rows.size(),1);
  EXPECT_EQ(rows[0].phrase,"星和");
  std::ifstream file(store.phrasesPath()); std::string text((std::istreambuf_iterator<char>(file)),{});
  EXPECT_EQ(text,"# custom note\n星和 ㄋㄧˇ-ㄏㄠˇ -2\n");
  EXPECT_FALSE(store.upsertPhrase({"其他","ㄋㄧˇ-ㄏㄠˇ"},reading,original));
  EXPECT_EQ(store.phrases().size(),1);
}
