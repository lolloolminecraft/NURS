import unittest
from monitor import candidate


class ReleaseTests(unittest.TestCase):
    def entry(self, name, body):
        return {
            "id": 20,
            "name": name,
            "tag_name": "v1",
            "body": body,
            "draft": False,
            "prerelease": False,
            "html_url": "https://github.com/GoldHEN/GoldHEN/releases/tag/v1",
            "assets": [{"name": "release.zip", "browser_download_url": "https://github.com/GoldHEN/GoldHEN/releases/download/v1/release.zip"}]
        }

    def test_positive(self):
        self.assertIsNotNone(candidate(self.entry("PS4 14.00 jailbreak", "Working full jailbreak with setup steps"), "GoldHEN/GoldHEN"))

    def test_wrong_version(self):
        self.assertIsNone(candidate(self.entry("PS4 13.04 jailbreak", "Full jailbreak"), "GoldHEN/GoldHEN"))

    def test_only_research(self):
        self.assertIsNone(candidate(self.entry("PS4 14.00 WebKit", "Research only, not a jailbreak. Needs new KEX"), "GoldHEN/GoldHEN"))

    def test_needs_download(self):
        entry = self.entry("PS4 14.00 jailbreak", "Working jailbreak")
        entry["assets"] = []
        self.assertIsNone(candidate(entry, "GoldHEN/GoldHEN"))


if __name__ == "__main__":
    unittest.main()
