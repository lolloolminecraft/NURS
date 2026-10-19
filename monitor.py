import json
import os
import re
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parent
STATUS = ROOT / "docs" / "status.json"


def utc_now():
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def github_releases(repository):
    url = f"https://api.github.com/repos/{repository}/releases?per_page=15"
    headers = {"Accept": "application/vnd.github+json", "User-Agent": "NURS-Release-Watch"}
    if os.getenv("GITHUB_TOKEN"):
        headers["Authorization"] = f"Bearer {os.environ['GITHUB_TOKEN']}"
    with urlopen(Request(url, headers=headers), timeout=20) as response:
        return json.load(response)


def candidate(release, repository):
    if release.get("draft") or release.get("prerelease"):
        return None
    body = release.get("body") or ""
    text = "\n".join([release.get("name") or "", release.get("tag_name") or "", body])
    if not re.search(r"(?<!\d)14(?:[._-]00|\.0)(?!\d)", text, re.I):
        return None
    if re.search(r"not a jailbreak|no jailbreak|not supported|unsupported|not working|not available|not yet|coming soon|research only|still needs|needs new kex", text, re.I):
        return None
    if not re.search(r"jailbreak|jailbroken|full exploit chain|working exploit chain", text, re.I):
        return None
    assets = [a for a in release.get("assets", []) if a.get("browser_download_url") and re.search(r"\.(zip|7z|rar|tar|gz|bin|elf|pkg|iso)$", a.get("name", ""), re.I)]
    if not assets or not release.get("html_url"):
        return None
    urls = re.findall(r"https?://(?:www\.)?(?:youtube\.com/watch\?[^\s)<>]+|youtu\.be/[\w-]+|youtube\.com/shorts/[\w-]+)", body)
    return {
        "id": f"{repository}#{release.get('id', release.get('tag_name', ''))}",
        "title": release.get("name") or release.get("tag_name") or "PS4 14.00",
        "source": repository,
        "source_url": release["html_url"],
        "download_url": assets[0]["browser_download_url"],
        "instructions": body[:12000],
        "video_url": urls[0].rstrip(".,;") if urls else "",
        "published_at": release.get("published_at") or ""
    }


def detect(repositories):
    matches = []
    errors = []
    for repo in repositories:
        if not re.fullmatch(r"[a-zA-Z0-9_.-]+/[a-zA-Z0-9_.-]+", repo):
            raise ValueError("Invalid repository name")
        try:
            releases = github_releases(repo)
            for release in releases:
                item = candidate(release, repo)
                if item:
                    matches.append(item)
        except (HTTPError, URLError, TimeoutError) as exc:
            errors.append(f"{repo}: {exc}")
    if errors:
        print("Source check failed: " + "; ".join(errors), file=sys.stderr)
    if len(errors) == len(repositories):
        raise RuntimeError("All release sources failed")
    return sorted(matches, key=lambda r: r["published_at"], reverse=True)[0] if matches else None


def notify(release, detected_at):
    token = os.getenv("WHATSAPP_TOKEN", "").strip()
    sender = os.getenv("WHATSAPP_PHONE_ID", "").strip()
    to = os.getenv("WHATSAPP_TO", "").strip()
    if not (token and sender and to):
        return "not_configured"
    version = os.getenv("META_GRAPH_VERSION") or "v26.0"
    if not re.fullmatch(r"v\d+\.\d+", version):
        raise ValueError("Invalid Meta Graph version")
    body = {
        "messaging_product": "whatsapp",
        "to": to,
        "type": "template",
        "template": {
            "name": os.getenv("WHATSAPP_TEMPLATE") or "nurs_ps4_release",
            "language": {"code": os.getenv("WHATSAPP_TEMPLATE_LANG") or "ru"},
            "components": [{"type": "body", "parameters": [
                {"type": "text", "text": release["download_url"]},
                {"type": "text", "text": os.getenv("NURS_SITE_URL") or release["source_url"]},
                {"type": "text", "text": detected_at}
            ]}]
        }
    }
    request = Request(
        f"https://graph.facebook.com/{version}/{sender}/messages",
        data=json.dumps(body).encode(),
        headers={"Content-Type": "application/json", "Authorization": f"Bearer {token}"},
        method="POST"
    )
    try:
        with urlopen(request, timeout=25) as response:
            reply = json.load(response)
        return "submitted" if reply.get("messages") else "failed"
    except (HTTPError, URLError, TimeoutError) as exc:
        print(f"WhatsApp API error: {exc}", file=sys.stderr)
        return "failed"


def main():
    config = json.loads((ROOT / "config.json").read_text(encoding="utf-8"))
    previous = json.loads(STATUS.read_text(encoding="utf-8"))
    release = detect(config["sources"])
    state = dict(previous)
    if release and state.get("state") != "released" and (state.get("release") or {}).get("id") != release["id"]:
        state = {"state": "candidate", "release": release, "detected_at": utc_now(), "submitted_at": None, "notification": "awaiting_verification", "last_checked_at": previous.get("last_checked_at")}
    if state.get("state") == "released" and state.get("notification") != "submitted":
        result = notify(state["release"], state.get("detected_at") or utc_now())
        state["notification"] = result
        if result == "submitted":
            state["submitted_at"] = utc_now()
    last = state.get("last_checked_at")
    try:
        recent = last and datetime.now(timezone.utc) - datetime.fromisoformat(last) < timedelta(hours=24)
    except (ValueError, TypeError):
        recent = False
    if not recent:
        state["last_checked_at"] = utc_now()
    if state != previous:
        STATUS.write_text(json.dumps(state, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print("Status file updated")
    else:
        print("No new release")
    print(f"status={state['state']} whatsapp={state.get('notification', 'not_sent')}")


if __name__ == "__main__":
    main()
