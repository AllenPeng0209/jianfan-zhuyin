#include "Session.h"
#include "gtest/gtest.h"
#include <algorithm>
#include <filesystem>
#include <fstream>

namespace {
Jianfan::Config config(bool simplified = true) {
  const std::string root = JIANFAN_SOURCE_ROOT;
  return {root + "/Vendor/McBopomofo/Source/Data/data.txt",
          root + "/Vendor/McBopomofo/Source/Data/associated-phrases-v2.txt",
          root + "/Vendor/Dependencies/SwiftyOpenCC/Sources/OpenCC/Dictionary", "", "", simplified};
}
void type(Jianfan::Session& session, const std::string& keys) {
  for (char key : keys) { ASSERT_TRUE(session.key(key, 1000)); }
}
}

TEST(Session, StandardBopomofoCompositionAndCommit) {
  Jianfan::Session session(config());
  ASSERT_TRUE(session.ready());
  type(session, "su3cl3");
  EXPECT_EQ(session.composition(), "你好");
  EXPECT_EQ(session.cursorUtf16(), 2);
  EXPECT_EQ(session.commit(), "你好");
  EXPECT_TRUE(session.composition().empty());
  EXPECT_TRUE(session.commit().empty());
}

TEST(Session, ScriptChangeRetainsTextAndIncompleteSyllable) {
  Jianfan::Session session(config(false));
  type(session, "gj bj4s");
  EXPECT_EQ(session.composition(), "輸入ㄋ");
  session.setSimplified(true);
  EXPECT_EQ(session.composition(), "输入ㄋ");
  session.backspace();
  EXPECT_EQ(session.composition(), "输入");
  session.setSimplified(false);
  EXPECT_EQ(session.composition(), "輸入");
}

TEST(Session, CandidateSelectionCanBeRestoredInANewSession) {
  Jianfan::Session first(config(false));
  type(first, "ru4");
  first.openCandidates();
  auto found = std::find_if(first.candidates().begin(), first.candidates().end(), [](const auto& c) { return c.value == "紀"; });
  ASSERT_NE(found, first.candidates().end());
  ASSERT_TRUE(first.selectCandidate(static_cast<size_t>(found - first.candidates().begin()), 1000));
  EXPECT_EQ(first.composition(), "紀");
  auto records = first.learnedChoices();
  ASSERT_FALSE(records.empty());
  Jianfan::Session second(config(false));
  second.restoreChoices(records);
  type(second, "ru4");
  EXPECT_EQ(second.composition(), "紀");
}

TEST(Session, AssociationsAppendOnlyTheirMissingReadings) {
  Jianfan::Session session(config(false));
  type(session, "5j/ cj86");
  session.openAssociations();
  ASSERT_FALSE(session.associations().empty());
  auto first = session.associations().front();
  ASSERT_TRUE(session.selectAssociation(0, 1000));
  EXPECT_EQ(session.composition(), first.value);
  EXPECT_EQ(session.commit(), first.value);
}

TEST(Session, InvalidReadingStaysEditableAndCancelOnlyClosesCandidates) {
  Jianfan::Session session(config());
  type(session, "su3cl3ni4");
  EXPECT_EQ(session.composition(), "你好ㄙㄛˋ");
  session.cancel();
  EXPECT_EQ(session.composition(), "你好");
  session.openCandidates();
  session.cancel();
  EXPECT_EQ(session.composition(), "你好");
}

TEST(Session, PhraseAwareConversionAndReadingValidation) {
  Jianfan::Session session(config());
  EXPECT_EQ(session.toSimplified("頭髮與發展"), "头发与发展");
  EXPECT_EQ(session.toTraditional("干净的头发"), "乾淨的頭髮");
  EXPECT_TRUE(session.supportsReading("ㄒㄧㄥ-ㄏㄜˊ"));
  EXPECT_FALSE(session.supportsReading("ㄅㄧㄚˇ"));
  EXPECT_EQ(session.suggestedReading("电脑"), "ㄉㄧㄢˋ-ㄋㄠˇ");
}
