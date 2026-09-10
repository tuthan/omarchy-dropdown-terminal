import QtQuick
import QtTest
import "../../PetVoice.js" as PetVoice

TestCase {
  name: "PetVoice"

  function document() {
    var line = function(value) { return [value, value + " again", "Another " + value,
      "One more " + value, "Five " + value, "Six " + value] }
    return {
      version: 1,
      tiers: {
        Kind: { failed: line("kind fail"), succeeded: line("kind win"), petting: line("kind pet"), idle: line("kind idle") },
        Sassy: { failed: ["Exit {status}? Bold strategy.", "Try again.", "Nope.", "That was quick.", "I saw that.", "Nearly."] , succeeded: line("sassy win"), petting: line("sassy pet"), idle: line("sassy idle") },
        Savage: { failed: line("sav fail"), succeeded: ["Only {duration}. I aged.", "Fine.", "Sure.", "Okay.", "Wow.", "Again."], petting: line("sav pet"), idle: line("sav idle") }
      },
      species: { Cat: { Sassy: { failed: ["Cat says {status}.", "Cat says no.", "Cat is unimpressed.", "Cat watches.", "Cat blinks.", "Cat naps."] } } },
      facts: { status: 1, duration: "over 10 min" }
    }
  }

  function test_document_validates() {
    verify(PetVoice.validateDocument(document()).valid)
  }

  function test_template_and_species_override() {
    compare(PetVoice.pickLine(document(), "Sassy", "failed", "Cat", [], 0, 3), "Cat says 1.")
  }

  function test_no_repeat_window() {
    var doc = document()
    var recent = ["kind fail", "kind fail again", "Another kind fail", "One more kind fail", "Five kind fail"]
    compare(PetVoice.pickLine(doc, "Kind", "failed", "Penguin", recent, 0, 3), "Six kind fail")
  }

  function test_unlocks_filter() {
    var doc = document()
    doc.tiers.Savage.succeeded = [
      { text: "locked", minPeakTier: 3 }, "a", "b", "c", "d", "e"
    ]
    compare(PetVoice.pickLine(doc, "Savage", "succeeded", "Penguin", [], 0, 0), "a")
    compare(PetVoice.pickLine(doc, "Savage", "succeeded", "Penguin", [], 0, 3), "locked")
  }

  function test_invalid_template_is_rejected() {
    var doc = document()
    doc.tiers.Kind.failed[0] = "bad {command}"
    verify(!PetVoice.validateDocument(doc).valid)
  }

  function test_unknown_event_is_rejected() {
    var doc = document()
    doc.tiers.Kind.result = doc.tiers.Kind.failed
    verify(!PetVoice.validateDocument(doc).valid)
  }
}
