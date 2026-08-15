from pathlib import Path
import re
import sys

text = Path("main.mo").read_text(encoding="utf-8")
match = re.search(r"system func postupgrade\(\) \{(?P<body>.*?)\n  \};", text, re.S)
if not match:
    print("missing_postupgrade")
    sys.exit(1)

body = match.group("body")
forbidden = [
    "HashMap.fromIter<Principal, Nat>(ticketEntries.vals()",
    "HashMap.fromIter<Nat, Nat>(costEntries.vals()",
    "HashMap.fromIter<Principal, Nat>(tokenEntries.vals()",
    "HashMap.fromIter<Text, NftListing>(nftListingEntries.vals()",
    "HashMap.fromIter<Text, GameSubmission>(gameSubmissionEntries.vals()",
    "HashMap.fromIter<Principal, Nat>(royaltyEntries.vals()",
    "HashMap.fromIter<Text, EscrowedNft>(escrowEntries.vals()",
    "HashMap.fromIter<Text, Nat>(gameRawTicketPoolEntries.vals()",
    "HashMap.fromIter<Text, Nat>(gameBackedTicketPoolEntries.vals()",
    "for (idx in claimedDeposits.vals())",
    "Buffer.fromArray<(Principal, Int)>(playLogEntries)",
    "for ((p, n, t) in dailyTicketEntries.vals())",
    "HashMap.fromIter<Principal, Nat>(accountPlayCountEntries.vals()",
    "HashMap.fromIter<Text, LeaderboardEntry>(leaderboardEntries.vals()",
]

hits = [needle for needle in forbidden if needle in body]
if hits:
    print("unsafe_postupgrade_hydration")
    for hit in hits:
        print(hit)
    sys.exit(1)

required_resets = [
    "claimedDeposits := [];",
    "playLogEntries := [];",
    "dailyTicketEntries := [];",
    "accountPlayCountEntries := [];",
]

missing_resets = [needle for needle in required_resets if needle not in body]
if missing_resets:
    print("missing_postupgrade_legacy_resets")
    for hit in missing_resets:
        print(hit)
    sys.exit(1)

# Leaderboard stable entries are intentionally preserved through postupgrade.
# The safety invariant is that postupgrade must not eagerly hydrate them from
# legacy stable bytes; runtime lazy hydration may rebuild the map after upgrade.
required_leaderboard_preservation = [
    "leaderboards := HashMap.HashMap<Text, LeaderboardEntry>",
    "Keep leaderboardEntries intact",
    "hydrateRuntimeStateIfNeeded() rebuilds",
]
missing_leaderboard_policy = [needle for needle in required_leaderboard_preservation if needle not in body]
if missing_leaderboard_policy:
    print("missing_leaderboard_preservation_policy")
    for hit in missing_leaderboard_policy:
        print(hit)
    sys.exit(1)

print("ok")
