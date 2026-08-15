from pathlib import Path

SOURCE = Path("main.mo").read_text(encoding="utf-8")
DID = Path(".build/arcade_backend.did").read_text(encoding="utf-8")
NORMALIZED_DID = " ".join(DID.split())
JAY_ADMIN_PRINCIPAL = "fb6so-esdgb-uuuco-wjwky-qzrmj-kbljo-62sbb-vxmjq-oxwsa-d7ufn-cqe"


def test_jay_admin_principal_is_in_static_admin_allowlist():
    admins_block = SOURCE.split("let ADMINS : [Principal] = [", 1)[1].split("];", 1)[0]
    assert f'Principal.fromText("{JAY_ADMIN_PRINCIPAL}")' in admins_block


def test_admin_principal_query_exposes_jay_admin_proof_surface():
    assert "transient let JAY_PRINCIPAL : Principal" in SOURCE
    assert "public query func isAdminPrincipal(principal : Principal) : async Bool" in SOURCE
    method_body = SOURCE.split("public query func isAdminPrincipal(principal : Principal) : async Bool", 1)[1].split("\n\n", 1)[0]
    assert "isAdmin(principal)" in method_body
    assert "isAdminPrincipal: (\"principal\": principal) -> (bool) query" in NORMALIZED_DID


def test_admin_add_game_method_matches_frontend_upload_idl_and_is_admin_only():
    assert "public shared(msg) func adminAddGame(" in SOURCE
    assert "paysTickets : Bool" in SOURCE
    assert "screenshots : [Text]" in SOURCE
    assert "tokenCost : Nat" in SOURCE
    assert "purchasePrice : Nat" in SOURCE
    method_body = SOURCE.split("public shared(msg) func adminAddGame(", 1)[1].split("\n  ///", 1)[0]
    assert "if (not isAdmin(msg.caller)) return #err(\"Not authorized\")" in method_body
    assert "hydrateRuntimeStateIfNeeded();" in method_body
    assert "let id = genGameId();" in method_body
    assert "gameSubmissions.put(id, game);" in method_body
    assert "status = \"live\";" in method_body
    assert "#ok(id)" in method_body
    assert "adminAddGame: (name: text, developer: text, url: text, thumbnailUrl: text, description: text, compatibility: text, creator: principal, gameTier: text, paysTickets: bool, screenshots: vec text, category: text, tokenCost: nat, scoring: text, purchasePrice: nat) -> (Result_3)" in NORMALIZED_DID


def test_admin_get_all_games_is_admin_guarded_and_in_declared_candid():
    assert "public shared(msg) func adminGetAllGames()" in SOURCE
    method_body = SOURCE.split("public shared(msg) func adminGetAllGames()", 1)[1].split("\n  ///", 1)[0]
    assert "if (not isAdmin(msg.caller)) return []" in method_body
    assert "hydrateRuntimeStateIfNeeded();" in method_body
    assert "Iter.toArray(gameSubmissions.vals())" in method_body
    assert "adminGetAllGames: () -> (vec GameSubmission)" in NORMALIZED_DID


def test_admin_add_game_does_not_migrate_game_submission_schema():
    game_type = SOURCE.split("type GameSubmission = {", 1)[1].split("  };", 1)[0]
    for field in ["paysTickets", "screenshots", "category", "tokenCost", "scoring", "purchasePrice"]:
        assert field not in game_type
