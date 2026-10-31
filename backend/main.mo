import Principal "mo:base/Principal";
import HashMap "mo:base/HashMap";
import Nat "mo:base/Nat";
import Nat64 "mo:base/Nat64";
import Int "mo:base/Int";
import Result "mo:base/Result";
import Time "mo:base/Time";
import Iter "mo:base/Iter";
import Buffer "mo:base/Buffer";
import Array "mo:base/Array";
import Error "mo:base/Error";
import Hash "mo:base/Hash";
import Nat32 "mo:base/Nat32";
import Text "mo:base/Text";
import Trie "mo:base/Trie";
import Option "mo:base/Option";
import Bool "mo:base/Bool";
import Blob "mo:base/Blob";
import Char "mo:base/Char";
import Nat8 "mo:base/Nat8";
import Timer "mo:base/Timer";
import Random "mo:base/Random";

persistent actor ArcadeBackend {

  func natHash(n : Nat) : Hash.Hash {
    Nat32.fromNat(n % 4294967296);
  };
  func natEqual(a : Nat, b : Nat) : Bool { a == b };
  func textHash(t : Text) : Hash.Hash {
    Text.hash(t);
  };

  // === TYPES ===
  type TokenId = Nat;
  type Account = { owner : Principal; subaccount : ?Blob };
  type TransferArg = {
    to : Account;
    spender_subaccount : ?Blob;
    from : ?Account;
    memo : ?Blob;
    is_atomic : ?Bool;
    token_ids : [Nat];
    created_at_time : ?Nat64;
  };
  type TransferResult = {
    #Ok : [Nat];
    #Err : {
      #Unauthorized : { token_ids : [Nat] };
      #TooOld;
      #CreatedInFuture : { ledger_time : Nat64 };
      #Duplicate : { duplicate_of : Nat };
      #GenericError : { error_code : Nat; message : Text };
      #TemporarilyUnavailable;
      #GenericBatchError : { error_code : Nat; message : Text };
    };
  };
  // Matches nft.mo's Metadata/MetadataValue shape exactly, for calling mint/mintBatch there.
  type NftMetadataValue = {
    #Nat : Nat;
    #Int : Int;
    #Text : Text;
    #Blob : Blob;
    #Map : [(Text, NftMetadataValue)];
    #Array : [NftMetadataValue];
  };
  type NftMetadata = [(Text, NftMetadataValue)];

  // === DIP-721 STANDARD TYPES ===
  type Dip721TransferResult = {
    #Ok : Nat;
    #Err : {
      #UnauthorizedOwner;
      #UnauthorizedOperator;
      #OwnerNotFound;
      #TokenNotFound;
      #ExistedNFT;
      #SelfTransfer;
      #Other : Text;
    };
  };

  // Create dynamic DIP-721 actor for any canister
  func getDip721Actor(canisterId : Text) : actor {
    ownerOfDip721 : shared query (Nat64) -> async { #Ok : Principal; #Err : { #TokenNotFound; #Other : Text } };
    transferFromDip721 : shared (Principal, Principal, Nat64) -> async Dip721TransferResult;
  } {
    actor(canisterId);
  };

  // Create dynamic ICRC-7 actor for any canister (for user-listed NFTs)
  func getDynamicIcrc7Actor(canisterId : Text) : actor {
    icrc7_owner_of : shared query (Nat) -> async { #Ok : Account; #Err : { #InvalidTokenId } };
    icrc7_transfer : shared (TransferArg) -> async TransferResult;
  } {
    actor(canisterId);
  };

  // Escrowed NFT type (NFTs held by arcade for sale)
  type EscrowedNft = {
    listingId : Text;
    canisterId : Text; // source canister (EXT or ICRC-7)
    tokenId : Text; // token identifier (EXT text or ICRC-7 numeric as text)
    standard : Text; // "icrc7" or "dip721"
    depositor : Principal; // who deposited (creator)
    depositedAt : Int;
    status : Text; // "held", "redeemed", "returned"
    redeemedBy : ?Principal; // buyer if redeemed
    redeemedAt : ?Int;
  };

  // NFT Listing type
  type NftListing = {
    id : Text;
    listingType : Text; // "mint" or "existing"
    name : Text;
    description : Text;
    rarity : Text;
    ticketCost : Nat;
    imageUrl : Text; // URL or data URI
    creator : Principal;
    tier : Text; // "open", "showroom", "showroom-pending", "jays-picks"
    status : Text; // "pending_escrow", "live", "removed"
    feePaid : Nat; // in e8s
    showroomFeePaid : Nat; // in e8s (for showroom escrow)
    txId : Nat;
    createdAt : Int;
    // For existing NFTs
    sourceCanisterId : Text;
    sourceTokenId : Nat;
    sourceTokenKey : Text; // full token identifier; EXT keeps text ids like ckbgq...-9054
    collectionName : Text;
  };

  // Official arcade collection record. Additive-only state for admin-curated
  // internal prize booth mints; no external NFT/cycles/token transfers occur here.
  type OfficialCollection = {
    id : Text;
    name : Text;
    description : Text;
    creator : Principal;
    imageUrls : [Text];
    nftIds : [Nat];
    ticketCost : Nat;
    totalSupply : Nat;
    abilities : [(Text, Text)];
    createdAt : Int;
  };

  // Old-compatible stable representation for listings. Do not add sourceTokenKey here:
  // deployed stable memory contains records without that field, so runtime-only
  // NftListing hydrates sourceTokenKey from the additive key array or fallback.
  type NftListingStable = {
    id : Text;
    listingType : Text;
    name : Text;
    description : Text;
    rarity : Text;
    ticketCost : Nat;
    imageUrl : Text;
    creator : Principal;
    tier : Text;
    status : Text;
    feePaid : Nat;
    showroomFeePaid : Nat;
    txId : Nat;
    createdAt : Int;
    sourceCanisterId : Text;
    sourceTokenId : Nat;
    collectionName : Text;
  };

  // Game Submission type
  type GameSubmission = {
    id : Text;
    name : Text;
    developer : Text;
    url : Text;
    thumbnailUrl : Text;
    description : Text;
    compatibility : Text; // "both", "mobile", "desktop"
    creator : Principal;
    gameTier : Text; // "backroom", "showroom", "jays-picks" (legacy "showroom-pending" tier removed in session #3)
    status : Text; // "live", "removed"
    feePaid : Nat; // in e8s
    showroomFeePaid : Nat; // in e8s
    txId : Nat;
    createdAt : Int;
  };

  // Chunked zip-upload queue for user-submitted game zips (The Back and Showroom).
  // Submitters upload directly into arcade_backend's own storage (the only canister every
  // authenticated user can freely call) since only the admin identity has write permission on the
  // real game_assets hosting canister. Admin then downloads and personally reviews the zip before
  // manually publishing it via the existing admin-only "Upload Game to Chain" tool — this queue
  // deliberately does not auto-publish anything.
  // Simple per-user notification for submission accept/reject events, so a submitter gets a
  // real popup next time they load the app rather than silently wondering what happened.
  type UserNotification = {
    id : Text;
    recipient : Principal;
    title : Text;
    message : Text;
    gameId : Text;
    createdAt : Int;
    seen : Bool;
  };

  type PendingZipUpload = {
    id : Text;
    gameId : Text; // the GameSubmission this file belongs to
    submitter : Principal;
    tier : Text; // "backroom" or "showroom", carried for the admin queue's own display/filtering
    // filename is prefixed "thumbnail::" or "zip::" to distinguish purpose without a stable-type
    // shape change — this type was already deployed once without a dedicated field, and adding
    // one on a second deploy trips Motoko's memory-incompatible-upgrade guard on the existing
    // stable data. A new field can still be added safely on a genuinely fresh reinstall later.
    filename : Text;
    totalBytes : Nat;
    chunkCount : Nat;
    receivedChunks : Nat;
    status : Text; // "uploading", "ready", "downloaded"
    createdAt : Int;
  };


  // Shared forum / DAO proposal types (additive stable state, advisory only).
  type ForumReply = {
    id : Text;
    threadId : Text;
    body : Text;
    image : ?Text;
    author : Principal;
    authorName : Text;
    createdAt : Int;
    parentReplyId : ?Text;
  };
  type ForumThread = {
    id : Text;
    section : Text;
    title : Text;
    body : Text;
    image : ?Text;
    author : Principal;
    authorName : Text;
    createdAt : Int;
    replies : [ForumReply];
    deleted : Bool;
  };
  type HoleSubmission = {
    id : Text;
    title : Text;
    description : Text;
    url : Text;
    creator : Principal;
    creatorNameSnapshot : Text;
    createdAt : Int;
    upvotes : Nat;
    status : Text; // "active" | "deleted" (punishment-related statuses added later)
    isLegendary : Bool;
  };
  type HolePunishment = {
    principal : Principal;
    until : Int; // ignored when permanent is true
    permanent : Bool;
    reason : Text;
  };
  type HoleVote = {
    submissionId : Text;
    voter : Principal;
    isLike : Bool;
    timestamp : Int;
  };
  // Real, backend-persisted replacement for the old localStorage-only game like/dislike system —
  // that version never left the browser it was cast in, so no vote ever actually reached other
  // users; "Most Upvoted" never reflected real community sentiment. Toggleable (unlike Blackhole's
  // permanent vote), matching the existing frontend UX: clicking the same vote again removes it,
  // clicking the other one changes it. Open to any connected user, no Voting Power gate — this is
  // a lightweight community signal on The Back, not a DAO governance action like Blackhole's.
  type GameVote = {
    gameId : Text;
    voter : Principal;
    isLike : Bool;
    timestamp : Int;
  };
  type GamerBadge = {
    id : Text;
    badgeType : Text;
    owner : Principal;
    gameId : ?Text;
    votingPower : Nat;
    soulbound : Bool;
    createdAt : Int;
  };
  // Real on-chain player profile — name/bio/avatar visible to anyone, not just the owner's own
  // browser. Previously the frontend called setPlayerProfile/getPlayerProfile as if these
  // existed; neither did, so no player's name has ever actually been visible to anyone else.
  type PlayerProfile = {
    name : Text;
    bio : Text;
    avatarUrl : Text;
    createdAt : Int;
    lastSeen : Int;
  };
  type DirectoryPlayer = {
    principal : Principal;
    name : Text;
    bio : Text;
    avatarUrl : Text;
    lastSeen : Int;
  };
  type ProposalVote = {
    voter : Principal;
    vote : Text;
    weight : Nat;
    timestamp : Int;
  };
  type ProposalDiscussion = {
    author : Principal;
    authorName : Text;
    body : Text;
    timestamp : Int;
  };
  type Proposal = {
    id : Text;
    title : Text;
    body : Text;
    category : Text;
    official : Bool;
    images : [Text];
    author : Principal;
    authorName : Text;
    createdAt : Int;
    endsAt : Int;
    duration : Text;
    votesFor : Nat;
    votesAgainst : Nat;
    votes : [ProposalVote];
    discussion : [ProposalDiscussion];
    closed : Bool;
  };
  type DaoStats = {
    proposals : Nat;
    activeProposals : Nat;
    badgeHolders : Nat;
    forumThreads : Nat;
  };

  type TipReceipt = {
    id : Text;
    gameId : Text;
    creator : Principal;
    tipper : Principal;
    amountE8s : Nat;
    anonymous : Bool;
    displayName : Text;
    txRef : Text;
    createdAt : Int;
  };

  type IcpTipSummary = {
    totalE8s : Nat;
    count : Nat;
  };

  // Platform-wide revenue event log; this is not DAO reward accounting.
  type RevenueEvent = {
    eventType : Text; // "nft-list", "nft-mint", "nft-showroom", "game-backroom", "game-showroom", "token-purchase", "nft-redeem"
    amount : Nat; // in e8s
    from : Principal;
    memo : Nat; // 1=list, 2=mint, 3=nft-showroom, 4=game-backroom, 5=game-showroom, 6=token-purchase
    timestamp : Int;
  };

  type GameRawTicketPoolSnapshot = {
    gameId : Text;
    rawTicketPool : Nat;
  };

  type GameBackedTicketPoolSnapshot = {
    gameId : Text;
    backedTicketPool : Nat;
  };

  type TicketReserveAuditSnapshot = {
    totalRawTicketPool : Nat;
    totalBackedTicketPool : Nat;
    outstandingBackedLiability : Nat;
    coverageGap : Nat;
    surplusBacking : Nat;
    unbackedRawExposure : Nat;
    ticketGameCount : Nat;
  };

  type TreasuryBalanceSnapshot = {
    balanceE8s : Nat;
    reservedE8s : Nat;
    outstandingTokens : Nat;
    withdrawableE8s : Nat;
    tokenLiabilityE8s : Nat;
    royaltyLiabilityE8s : Nat;
    refundLiabilityE8s : Nat;
    ticketPoolLiabilityE8s : Nat;
    ticketHolderLiabilityE8s : Nat;
    backedTicketPoolTickets : Nat;
    safetyBufferE8s : Nat;
  };

  type TreasuryLaneSnapshot = {
    protectedAccountId : Text;
    operatingAccountId : Text;
    protectedBalanceE8s : Nat;
    operatingBalanceE8s : Nat;
    backendSafeWithdrawableE8s : Nat;
    protectedReservedE8s : Nat;
    operatingIncludedInBacking : Bool;
    operatingIncludedInBackendSafeMath : Bool;
  };

  type EconomyRates = {
    icpE8s : Nat;
    tokensPerIcp : Nat;
    ticketsPerIcp : Nat;
    tokenE8s : Nat;
    ticketE8s : Nat;
    sellerPayout100TicketsE8s : Nat;
    sellerPayout1000TicketsE8s : Nat;
  };

  type ClaimableEarningsBreakdown = {
    gameCreatorEarningsE8s : Nat;
    nftSellerEarningsE8s : Nat;
    refundE8s : Nat;
    totalClaimableE8s : Nat;
  };

  type PaidGameSession = {
    player : Principal;
    gameId : Text;
    tokenCost : Nat;
    openedAt : Int;
    open : Bool;
  };

  type GamePayoutConfig = {
    enabled : Bool;
    thresholds : [Nat];
    updatedAt : Int;
  };

  type GamePayoutConfigView = {
    gameId : Text;
    enabled : Bool;
    thresholds : [Nat];
    payouts : [Nat];
    updatedAt : Int;
  };

  // Legacy v1 config retained for upgrade-safe stable migration from the
  // original single-threshold jackpot controls.
  type GameTicketJackpotConfigV1 = {
    enabled : Bool;
    scoreThreshold : Nat;
    updatedAt : Int;
  };

  type GameTicketJackpotConfig = {
    enabled : Bool;
    lowScoreThreshold : Nat;
    lowPayoutPercent : Nat;
    highScoreThreshold : Nat;
    highPayoutPercent : Nat;
    newHighScorePayoutPercent : Nat;
    updatedAt : Int;
  };

  type GameTicketJackpotConfigView = {
    gameId : Text;
    enabled : Bool;
    lowScoreThreshold : Nat;
    lowPayoutPercent : Nat;
    highScoreThreshold : Nat;
    highPayoutPercent : Nat;
    newHighScorePayoutPercent : Nat;
    updatedAt : Int;
  };

  type TicketJackpotTierPayout = {
    tierLabel : Text;
    percent : Nat;
    uncappedTickets : Nat;
  };

  type TicketJackpotCalculation = {
    tickets : Nat;
    uncappedTickets : Nat;
    tierLabels : [Text];
    tierPayouts : [TicketJackpotTierPayout];
    capped : Bool;
  };

  // ICRC-7 NFT canister actor interface.
  // 2026-08-15: previously hardcoded to "fhu5f-siaaa-aaaad-afkmq-cai" — an ID that did not
  // match this project's actual NFT canister (verified against production frontend,
  // which used a different ID entirely). Now a settable stable var, defaulting to
  // anonymous/unset so a stale or wrong ID can never be silently deployed again.
  // Set the real ID after the NFT canister is deployed via adminSetNftCanisterId().
  stable var nftCanisterIdText : Text = "aaaaa-aa"; // "aaaaa-aa" = IC management canister ID, used as an obvious placeholder that will fail loudly rather than silently pointing at someone else's canister

  type NftCanisterActor = actor {
    icrc7_transfer : shared (TransferArg) -> async TransferResult;
    icrc7_owner_of : shared query (Nat) -> async { #Ok : Account; #Err : { #InvalidTokenId } };
    icrc7_total_supply : shared query () -> async Nat;
    mintBatch : shared (Account, [NftMetadata]) -> async [Nat];
  };

  func nftCanister() : NftCanisterActor {
    actor (nftCanisterIdText) : NftCanisterActor;
  };

  /// Admin-only: point the backend at the real NFT canister once it's deployed.
  public shared(msg) func adminSetNftCanisterId(canisterId : Text) : async Result.Result<Text, Text> {
    assert (not isBannedNow(msg.caller)); // banned: only withdrawals, claims and listing allowed
    if (not isAdmin(msg.caller)) return #err("Not authorized");
    nftCanisterIdText := canisterId;
    #ok("NFT canister ID set to " # canisterId);
  };

  public query func getNftCanisterId() : async Text {
    nftCanisterIdText;
  };

  // === CONFIG ===
  // Backdoor principals removed 2026-08-15: previously contained two "other agent"
  // principals (7uj7m-..., xcreu-...) flagged as critical in the 2026-03-13 audit but
  // never removed, plus a third (fb6so-...) not attributable to the project owner.
  // ADMINS is now empty; sole admin authority is JAY_PRINCIPAL below.
  transient let ADMINS : [Principal] = [];

  // Sole admin principal (Infinity-Arcade-Identity, set 2026-08-15)
  transient let JAY_PRINCIPAL : Principal = Principal.fromText("fvuhj-qdha4-tu5gc-4hvim-yaxae-g5grp-xjiz3-u5rpo-5cniw-gpolf-eqe");

  // Treasury = this canister
  transient let TREASURY : Principal = Principal.fromActor(ArcadeBackend);

  // Reserve floor for auto cycle conversion (10 ICP = 1_000_000_000 e8s)
  transient let RESERVE_FLOOR_E8S : Nat = 1_000_000_000;

  // === FIXED ECONOMY RATE CONSTANTS ===
  // Phase 1 accounting invariant source of truth:
  // - 1 ICP = 100,000,000 e8s
  // - 1 ICP = 100 Tokens, so 1 Token = 1,000,000 e8s
  // - 1 ICP = 1,000 Tickets, so 1 Ticket = 100,000 e8s
  transient let ICP_E8S : Nat = 100_000_000;
  transient let TOKENS_PER_ICP : Nat = 100;
  transient let TICKETS_PER_ICP : Nat = 1_000;
  transient let TOKEN_LIABILITY_E8S : Nat = 1_000_000;
  transient let TICKET_LIABILITY_E8S : Nat = 100_000;
  // PRE-MAINNET: set to false. Admin mint tools (creditTokens, addTickets, winTickets, awardTickets,
  // creditRoyalty, adminSetTickets increases) create balances with no ICP behind them - local testing only.
  transient let ALLOW_TEST_MINTING : Bool = true;
  transient let TREASURY_SAFETY_BUFFER_E8S : Nat = 10_000;

  func ticketCostToSellerPayoutE8s(ticketCost : Nat) : Nat {
    ticketCost * TICKET_LIABILITY_E8S;
  };

  // === REVENUE SPLIT CONSTANTS (Economy v6) ===
  // Showroom ticket games: 80% to game's ticket pool (8 tickets per Token), 10% to game dev, 5% arcade, 5% DAO.
  // Supersedes the old, never-wired "5% burn" concept - that 10% is now an explicit, tracked
  // arcade-share accumulator (see showroomTicketArcadeShareE8s) rather than an untracked remainder.
  transient let TICKET_GAME_CREATOR_SHARE : Nat = 10; // percent
  transient let TICKET_GAME_DAO_SHARE : Nat = 5; // percent
  transient let TICKET_GAME_ARCADE_SHARE : Nat = 5; // percent
  transient let TICKET_GAME_POOL_SHARE : Nat = 80; // percent
  // The Back's regular/non-ticket games: 50% to game dev, 30% arcade, 20% DAO.
  transient let REGULAR_GAME_CREATOR_SHARE : Nat = 50; // percent
  transient let REGULAR_GAME_DAO_SHARE : Nat = 20; // percent
  transient let REGULAR_GAME_ARCADE_SHARE : Nat = 30; // percent
  // NFT sales: 90% to NFT creator, 10% stays in operating treasury; not DAO jackpot or member reward funding.
  transient let NFT_CREATOR_SHARE : Nat = 90; // percent

  // NFT listing fee: 5 Tokens = 0.05 ICP equivalent at the fixed 1 ICP = 100 Tokens rate (credits the Prize Booth arcade share).
  transient let NFT_LISTING_FEE_TOKENS : Nat = 5;
  transient let NFT_LISTING_FEE_E8S : Nat = NFT_LISTING_FEE_TOKENS * TOKEN_LIABILITY_E8S;

  // Backend canister's own default account identifier, used as the "protected" Treasury lane
  // account (see getTreasuryLaneSnapshot). Also matches the default AccountIdentifier for
  // pifyq-raaaa-aaaab-agrqq-cai from when this was additionally used for EXT bearer
  // verification, before EXT NFT standard support was removed.
  transient let SELF_ACCOUNT_ID : Text = "2b239054e41a561e39350c1e86fa53f97ba4acf8b40600574ea965ac11164ebb";

  // Operating Treasury lane: backend-owned subaccount derived from the literal
  // "operating-treasury" using the same length-prefixed lane convention as the frontend.
  // Account id is precomputed from pifyq-raaaa-aaaab-agrqq-cai + this subaccount.
  transient let OPERATING_TREASURY_ACCOUNT_ID : Text = "494ce8a2ea444907ba9e6191e747b7eb35e54f4b27a77796ed3aba10dbded490";
  transient let OPERATING_TREASURY_SUBACCOUNT : Blob = Blob.fromArray([
    18, 111, 112, 101, 114, 97, 116, 105,
    110, 103, 45, 116, 114, 101, 97, 115,
    117, 114, 121, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0,
  ]);
  // Dedicated Blackhole submission-fee subaccount, distinct from the shared Operating Treasury —
  // built so Blackhole's earnings/withdrawals stay separately trackable once other features
  // (Showroom, The Back) get their own real-ICP fees and subaccounts too.
  transient let BLACKHOLE_TREASURY_SUBACCOUNT : Blob = Blob.fromArray([
    18, 98, 108, 97, 99, 107, 104, 111,
    108, 101, 45, 116, 114, 101, 97, 115,
    117, 114, 121, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0,
  ]);
  // Dedicated The Back submission-fee subaccount, same reasoning as the Blackhole one — kept
  // separate so each feature's earnings/withdrawals stay independently trackable.
  transient let BACK_TREASURY_SUBACCOUNT : Blob = Blob.fromArray([
    13, 98, 97, 99, 107, 45, 116, 114,
    101, 97, 115, 117, 114, 121, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0,
  ]);
  transient let SHOWROOM_TREASURY_SUBACCOUNT : Blob = Blob.fromArray([
    17, 115, 104, 111, 119, 114, 111, 111,
    109, 45, 116, 114, 101, 97, 115, 117,
    114, 121, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0,
  ]);

  // === STABLE STATE ===
  // Existing (v1)
  stable var ticketEntries : [(Principal, Nat)] = [];
  // GXP: soulbound "Game Experience" stat — 10 GXP per Token spent, 1 GXP per Ticket earned
  // through real gameplay only (never from admin credits). Only ever increases, no admin
  // override exists to change it. maxGxpEverSeen tracks the site-wide high score incrementally
  // so the frontend can compute a color-scale ratio without an O(n) scan on every query.
  stable var gxpEntries : [(Principal, Nat)] = [];
  stable var maxGxpEverSeen : Nat = 0;
  // DXP: soulbound "DAO Experience" stat — number of badges held per vote cast, plus 10 flat
  // per proposal created. Same soulbound rules as GXP: only increases, no admin override.
  stable var dxpEntries : [(Principal, Nat)] = [];
  stable var maxDxpEverSeen : Nat = 0;
  // MXP: soulbound "Market Experience" stat — 21 MXP for redeeming any NFT from Prize Booth,
  // plus 12 MXP to a seller when someone redeems their user-listed NFT (mint/Official listings
  // have no real individual seller, so no seller-side MXP there). Same soulbound rules as
  // GXP/DXP: only increases, no admin override.
  stable var mxpEntries : [(Principal, Nat)] = [];
  stable var maxMxpEverSeen : Nat = 0;
  stable var playerProfileEntries : [(Principal, PlayerProfile)] = [];
  stable var costEntries : [(TokenId, Nat)] = [];
  stable var redemptionLog : [(Principal, TokenId, Int)] = [];
  stable var defaultCost : Nat = 50;

  // New (v2) - Token balances
  stable var tokenEntries : [(Principal, Nat)] = [];

  // New (v2) - NFT listings
  stable var nftListingEntries : [(Text, NftListingStable)] = [];
  // Additive stable storage for Phase 1 sourceTokenKey. Keeping this separate
  // avoids changing the deployed nftListingEntries record shape.
  stable var nftListingSourceTokenKeyEntries : [(Text, Text)] = [];
  stable var nftListingCounter : Nat = 0;

  // Official collections are additive state, separate from the legacy listing record shape.
  stable var officialCollectionEntries : [(Text, OfficialCollection)] = [];
  stable var officialCollectionAbilityEntries : [(Nat, Text)] = [];
  stable var officialCollectionCounter : Nat = 0;
  stable var disabledAbilityEntries : [Text] = [];
  stable var externalCollectionEntries : [(Text, Text)] = [];
  // Permission tags per moderator are unused today (empty list) but let future moderator
  // powers be added without redesigning storage.
  stable var moderatorEntries : [(Principal, [Text])] = [];

  // New (v2) - Game submissions
  stable var gameSubmissionEntries : [(Text, GameSubmission)] = [];
  stable var gameSubmissionCounter : Nat = 0;
  stable var zipUploadCounter : Nat = 0;
  stable var notificationCounter : Nat = 0;

  // New (v2) - Revenue log
  stable var revenueLogEntries : [RevenueEvent] = [];

  // New (v2) - Legacy game creator royalty balances (ICP e8s).
  // Phase 2 keeps this stable shape for migration compatibility and treats it as game creator earnings.
  stable var royaltyEntries : [(Principal, Nat)] = [];
  // Separate claimable pool for Token-based creator tips, distinct from royalties (game-token-spend earnings).
  stable var tipEarningsEntries : [(Principal, Nat)] = [];
  stable var pendingZipUploadEntries : [(Text, PendingZipUpload)] = [];
  stable var zipChunkEntries : [(Text, Blob)] = []; // key = uploadId # "#" # Nat.toText(chunkIndex)
  stable var notificationEntries : [(Text, UserNotification)] = [];
  // Category is stored separately (not on GameSubmission itself) since that stable type has
  // already been deployed multiple times tonight — adding a field now would trip the same
  // memory-incompatible-upgrade trap hit earlier with PendingZipUpload's purpose field.
  stable var gameCategoryEntries : [(Text, Text)] = []; // gameId -> category
  // Same reasoning as gameCategoryEntries/gamePricingEntries above: this cannot live as new fields
  // on GameSubmission (confirmed unsafe under this project's enhanced-orthogonal-persistence build,
  // even for optional fields), so it gets its own stable map. Tuple order: (keyboardOnly,
  // keyboardAndMouse, controllerReady, madeWithAi). Set by the submitter at submission time or any
  // time by admin, same auth pattern as category.
  stable var gameAccessibilityEntries : [(Text, (Bool, Bool, Bool, Bool))] = [];
  // Creator-declared monetization intent (paysTickets, wantsPurchasable). paysTickets is the real,
  // authoritative source of ticket-pool eligibility going forward - it replaces the old pure-tier
  // rule entirely (see isTicketGameSubmission below), no fallback needed since Jay confirmed
  // pre-existing test data doesn't need preserving. wantsPurchasable is just a request/hint shown
  // to admin in the pending-submission picker so they know to set a real purchasePrice via the
  // existing adminSetGamePricing tool when approving - it does not itself set any price.
  stable var gameMonetizationEntries : [(Text, (Bool, Bool))] = [];
  // Same reasoning as gameCategoryEntries above: pricing lives in its own stable map rather than
  // as fields on GameSubmission, since that record type cannot safely gain new fields at all under
  // this project's enhanced-orthogonal-persistence build (confirmed directly: even a new *optional*
  // field on GameSubmission trapped with "Memory-incompatible program upgrade" when attempted).
  // 0 in either slot of the tuple means "not set" (mirrors adminAddGame's existing convention).
  stable var gamePricingEntries : [(Text, (Nat, Nat))] = []; // gameId -> (tokenCost, purchasePrice)

  // New (v6) - NFT seller earnings (ICP e8s). Separate from game creator earnings and refunds.
  stable var nftSellerEarningEntries : [(Principal, Nat)] = [];

  // New (v5) - Refund balances (ICP e8s; separate from creator earnings/royalties)
  stable var refundEntries : [(Principal, Nat)] = [];

  // New (v2) - Platform-wide total revenue collected (in e8s), not DAO reward accounting.
  stable var totalRevenueE8s : Nat = 0;

  // New (v3) - NFT Escrow (held NFTs for Prize Booth sales)
  stable var escrowEntries : [(Text, EscrowedNft)] = []; // keyed by listingId



  // Phase 2 shared forums/proposals. These stable arrays are additive and do
  // not change existing stable record shapes.
  stable var forumThreadEntries : [ForumThread] = [];
  stable var forumThreadCounter : Nat = 0;
  stable var holeSubmissionEntries : [HoleSubmission] = [];
  stable var holeSubmissionCounter : Nat = 0;
  let HOLE_SUBMISSION_FEE_E8S : Nat = 100_000_000; // 1 ICP
  let BACK_SUBMISSION_FEE_E8S : Nat = 1_000_000_000; // 10 ICP
  let SHOWROOM_SUBMISSION_FEE_E8S : Nat = 2_500_000_000; // 25 ICP
  let MAX_ZIP_TOTAL_BYTES : Nat = 10 * 1024 * 1024; // 10MB, matches the existing admin upload tool's limit
  let MAX_ZIP_CHUNK_BYTES : Nat = 1_800_000; // ~1.8MB, safely under the IC's ~2MB per-call argument limit
  let MAX_PENDING_ZIP_UPLOADS_PER_USER : Nat = 6; // 2 uploads (zip+thumbnail) per game submission, so this allows up to 3 pending game submissions per user — was 3, which meant a user could never complete a second submission (its zip would use the last slot, then its thumbnail upload would fail)
  let MAX_THUMBNAIL_UPLOAD_BYTES : Nat = 2 * 1024 * 1024; // 2MB, matches the existing thumbnail cap
  stable var holePunishmentEntries : [HolePunishment] = [];
  let HOLE_SOFT_PUNISH_NS : Int = 7 * 24 * 60 * 60 * 1_000_000_000; // 7 days in nanoseconds
  stable var holeVoteEntries : [HoleVote] = [];
  stable var gameVoteEntries : [GameVote] = [];
  stable var gamerBadgeEntries : [GamerBadge] = [];
  stable var gamerBadgeCounter : Nat = 0;
  stable var proposalEntries : [Proposal] = [];
  stable var proposalCounter : Nat = 0;

  // === RUNTIME STATE ===
  transient var tickets = HashMap.HashMap<Principal, Nat>(32, Principal.equal, Principal.hash);
  transient var gxp = HashMap.HashMap<Principal, Nat>(32, Principal.equal, Principal.hash);
  transient var dxp = HashMap.HashMap<Principal, Nat>(32, Principal.equal, Principal.hash);
  transient var mxp = HashMap.HashMap<Principal, Nat>(32, Principal.equal, Principal.hash);
  transient var playerProfiles = HashMap.HashMap<Principal, PlayerProfile>(32, Principal.equal, Principal.hash);

  // Forum thread index: getForumThreads was doing a full linear scan + filter over EVERY thread
  // across ALL sections combined, on every single call — the highest-frequency read in the app,
  // and one whose cost only ever grows as more threads accumulate over the platform's life.
  // threadIdsBySection groups thread IDs by section (append-only — a reply never moves a thread
  // to a different section); threadsById holds each thread's current data, updated in place on
  // every reply. Lazily built once from forumThreadEntries, independent of the main hydration
  // flag since the forum system never used it.
  transient var forumIndexBuilt : Bool = false;
  transient var threadsById = HashMap.HashMap<Text, ForumThread>(64, Text.equal, textHash);
  transient var threadIdsBySection = HashMap.HashMap<Text, Buffer.Buffer<Text>>(16, Text.equal, textHash);

  func addThreadToIndex(thread : ForumThread) {
    threadsById.put(thread.id, thread);
    switch (threadIdsBySection.get(thread.section)) {
      case (?bucket) { bucket.add(thread.id) };
      case null {
        let bucket = Buffer.Buffer<Text>(8);
        bucket.add(thread.id);
        threadIdsBySection.put(thread.section, bucket);
      };
    };
  };

  func ensureForumIndexBuilt() {
    if (forumIndexBuilt) return;
    threadsById := HashMap.HashMap<Text, ForumThread>(forumThreadEntries.size() + 8, Text.equal, textHash);
    threadIdsBySection := HashMap.HashMap<Text, Buffer.Buffer<Text>>(16, Text.equal, textHash);
    for (thread in forumThreadEntries.vals()) { addThreadToIndex(thread) };
    forumIndexBuilt := true;
  };

  // Gamer Badge index: votingPowerOf, badgeCountOf, hasContributorBadge, vpBadgeCountOf,
  // getGamerBadges, and vpHolderPrincipals (used by the Player Portal directory) all used to
  // independently re-scan the entire gamerBadgeEntries array on every single call. Badges are
  // immutable once created (only ever created or removed, never edited in place), so a simple
  // owner -> [badges] grouping covers every one of these read patterns with no scan needed.
  transient var badgeIndexBuilt : Bool = false;
  transient var badgesByOwner = HashMap.HashMap<Principal, Buffer.Buffer<GamerBadge>>(64, Principal.equal, Principal.hash);

  func addBadgeToIndex(badge : GamerBadge) {
    switch (badgesByOwner.get(badge.owner)) {
      case (?bucket) { bucket.add(badge) };
      case null {
        let bucket = Buffer.Buffer<GamerBadge>(4);
        bucket.add(badge);
        badgesByOwner.put(badge.owner, bucket);
      };
    };
  };

  func ensureBadgeIndexBuilt() {
    if (badgeIndexBuilt) return;
    badgesByOwner := HashMap.HashMap<Principal, Buffer.Buffer<GamerBadge>>(64, Principal.equal, Principal.hash);
    for (badge in gamerBadgeEntries.vals()) { addBadgeToIndex(badge) };
    badgeIndexBuilt := true;
  };

  func getBadgesForOwner(owner : Principal) : [GamerBadge] {
    ensureBadgeIndexBuilt();
    switch (badgesByOwner.get(owner)) {
      case (?bucket) { Buffer.toArray(bucket) };
      case null { [] };
    };
  };
  transient var costs = HashMap.HashMap<Nat, Nat>(16, natEqual, natHash);
  transient var tokens = HashMap.HashMap<Principal, Nat>(32, Principal.equal, Principal.hash);
  transient var nftListings = HashMap.HashMap<Text, NftListing>(32, Text.equal, textHash);
  transient var officialCollections = HashMap.HashMap<Text, OfficialCollection>(8, Text.equal, textHash);
  transient var officialCollectionAbilities = HashMap.HashMap<Nat, Text>(32, natEqual, natHash);
  transient var disabledAbilities = HashMap.HashMap<Text, Bool>(8, Text.equal, textHash);
  transient var externalCollections = HashMap.HashMap<Text, Text>(8, Text.equal, textHash);
  transient var moderators = HashMap.HashMap<Principal, [Text]>(8, Principal.equal, Principal.hash);
  transient var gameSubmissions = HashMap.HashMap<Text, GameSubmission>(16, Text.equal, textHash);
  // Legacy name retained; this runtime map is the game creator earnings bucket.
  transient var royalties = HashMap.HashMap<Principal, Nat>(16, Principal.equal, Principal.hash);
  transient var tipEarnings = HashMap.HashMap<Principal, Nat>(16, Principal.equal, Principal.hash);
  transient var pendingZipUploads = HashMap.HashMap<Text, PendingZipUpload>(16, Text.equal, textHash);
  transient var zipChunks = HashMap.HashMap<Text, Blob>(64, Text.equal, textHash);
  transient var notifications = HashMap.HashMap<Text, UserNotification>(32, Text.equal, textHash);
  transient var gameCategories = HashMap.HashMap<Text, Text>(32, Text.equal, textHash);
  transient var gameAccessibility = HashMap.HashMap<Text, (Bool, Bool, Bool, Bool)>(32, Text.equal, textHash);
  transient var gameMonetization = HashMap.HashMap<Text, (Bool, Bool)>(32, Text.equal, textHash);
  transient var gamePricing = HashMap.HashMap<Text, (Nat, Nat)>(32, Text.equal, textHash);
  transient var nftSellerEarningsE8s = HashMap.HashMap<Principal, Nat>(16, Principal.equal, Principal.hash);
  transient var refundsE8s = HashMap.HashMap<Principal, Nat>(16, Principal.equal, Principal.hash);
  transient var escrows = HashMap.HashMap<Text, EscrowedNft>(16, Text.equal, textHash);
  transient var gameRawTicketPools = HashMap.HashMap<Text, Nat>(16, Text.equal, textHash);
  transient var gameBackedTicketPools = HashMap.HashMap<Text, Nat>(16, Text.equal, textHash);
  transient var paidGameSessions = HashMap.HashMap<Text, PaidGameSession>(16, Text.equal, textHash);
  transient var gamePurchases = HashMap.HashMap<Text, Bool>(16, Text.equal, textHash);
  transient var gameTokenSpend = HashMap.HashMap<Text, Nat>(16, Text.equal, textHash);
  transient var gamePayoutConfigs = HashMap.HashMap<Text, GamePayoutConfig>(16, Text.equal, textHash);
  transient var gameTicketJackpotConfigs = HashMap.HashMap<Text, GameTicketJackpotConfig>(16, Text.equal, textHash);
  transient var tipReceipts = Buffer.Buffer<TipReceipt>(0);
  transient var runtimeStateHydrated = false;

  // ICP ledger fee-sized floor: claiming less than this creates dust-level
  // payouts that are not worth moving before real volume starts.
  transient let ROYALTY_CLAIM_MIN_E8S : Nat = 20_000; // must exceed the ledger fee so a minimum claim still nets ICP
  // Session #3: users/claimants pay every ledger fee on ICP paid out of general custody - the platform
  // never absorbs it. Set explicitly (not fee = null) so a ledger fee change fails loudly with BadFee.
  transient let ICP_LEDGER_FEE_E8S : Nat = 10_000;
  // Ledger dedup: the ICP ledger rejects a second transfer with the same (from, to, amount, memo,
  // created_at_time) inside its 24h window as #Duplicate. Stamping every transfer makes an
  // accidental retry safe: the money can only move once.
  func ledgerNow() : Nat64 { Nat64.fromNat(Int.abs(Time.now())) };
  transient let ICP_TIP_MIN_E8S : Nat = 10_000;
  transient var operatingTreasuryWithdrawalInFlight = false;
  transient var blackholeTreasuryWithdrawalInFlight = false;
  transient var backTreasuryWithdrawalInFlight = false;
  transient var showroomTreasuryWithdrawalInFlight = false;

  // === UPGRADE HOOKS ===
  system func preupgrade() {
    if (runtimeStateHydrated) {
      ticketEntries := Iter.toArray(tickets.entries());
      gxpEntries := Iter.toArray(gxp.entries());
      dxpEntries := Iter.toArray(dxp.entries());
      mxpEntries := Iter.toArray(mxp.entries());
      playerProfileEntries := Iter.toArray(playerProfiles.entries());
      costEntries := Iter.toArray(costs.entries());
      tokenEntries := Iter.toArray(tokens.entries());
      let runtimeNftListingEntries = Iter.toArray(nftListings.entries());
      nftListingEntries := Array.map<(Text, NftListing), (Text, NftListingStable)>(
        runtimeNftListingEntries,
        func((listingId, listing)) { (listingId, nftListingToStable(listing)) }
      );
      nftListingSourceTokenKeyEntries := Array.map<(Text, NftListing), (Text, Text)>(
        runtimeNftListingEntries,
        func((listingId, listing)) { (listingId, listing.sourceTokenKey) }
      );
      officialCollectionEntries := Iter.toArray(officialCollections.entries());
      officialCollectionAbilityEntries := Iter.toArray(officialCollectionAbilities.entries());
      disabledAbilityEntries := Iter.toArray(disabledAbilities.keys());
      externalCollectionEntries := Iter.toArray(externalCollections.entries());
      moderatorEntries := Iter.toArray(moderators.entries());
      gameSubmissionEntries := Iter.toArray(gameSubmissions.entries());
      royaltyEntries := Iter.toArray(royalties.entries());
      tipEarningsEntries := Iter.toArray(tipEarnings.entries());
      pendingZipUploadEntries := Iter.toArray(pendingZipUploads.entries());
      zipChunkEntries := Iter.toArray(zipChunks.entries());
      notificationEntries := Iter.toArray(notifications.entries());
      gameCategoryEntries := Iter.toArray(gameCategories.entries());
      gameAccessibilityEntries := Iter.toArray(gameAccessibility.entries());
      gameMonetizationEntries := Iter.toArray(gameMonetization.entries());
      gamePricingEntries := Iter.toArray(gamePricing.entries());
      nftSellerEarningEntries := Iter.toArray(nftSellerEarningsE8s.entries());
      refundEntries := Iter.toArray(refundsE8s.entries());
      escrowEntries := Iter.toArray(escrows.entries());
      gameRawTicketPoolEntries := Iter.toArray(gameRawTicketPools.entries());
      gameBackedTicketPoolEntries := Iter.toArray(gameBackedTicketPools.entries());
      paidGameSessionEntries := Iter.toArray(paidGameSessions.entries());
      gamePurchaseEntries := Iter.toArray(gamePurchases.entries());
      gameTokenSpendEntries := Iter.toArray(gameTokenSpend.entries());
      gamePayoutConfigEntries := Iter.toArray(gamePayoutConfigs.entries());
      ticketJackpotWinEntries := Buffer.toArray(ticketJackpotWins);
      ticketJackpotWinTierEntries := Buffer.toArray(ticketJackpotWinDetails);
      gameTicketJackpotConfigV2Entries := Iter.toArray(gameTicketJackpotConfigs.entries());
      tipReceiptEntries := Buffer.toArray(tipReceipts);
      claimedDeposits := Iter.toArray(claimedSet.keys());
      playLogEntries := Buffer.toArray(playLog);
      dailyTicketEntries := Array.map<(Principal, (Nat, Int)), (Principal, Nat, Int)>(
        Iter.toArray(dailyTickets.entries()),
        func((p, (n, t))) { (p, n, t) }
      );
      accountPlayCountEntries := Iter.toArray(accountPlayCount.entries());
      leaderboardEntries := Iter.toArray(leaderboards.entries());
      playerBestEntries := Iter.toArray(playerBests.entries());
      profileWallEntries := Iter.toArray(profileWalls.entries());
    };
  };

  system func postupgrade() {
    tickets := HashMap.HashMap<Principal, Nat>(32, Principal.equal, Principal.hash);
    gxp := HashMap.HashMap<Principal, Nat>(32, Principal.equal, Principal.hash);
    dxp := HashMap.HashMap<Principal, Nat>(32, Principal.equal, Principal.hash);
    mxp := HashMap.HashMap<Principal, Nat>(32, Principal.equal, Principal.hash);
    playerProfiles := HashMap.HashMap<Principal, PlayerProfile>(32, Principal.equal, Principal.hash);
    costs := HashMap.HashMap<Nat, Nat>(16, natEqual, natHash);
    tokens := HashMap.HashMap<Principal, Nat>(32, Principal.equal, Principal.hash);
    nftListings := HashMap.HashMap<Text, NftListing>(32, Text.equal, textHash);
    officialCollections := HashMap.HashMap<Text, OfficialCollection>(8, Text.equal, textHash);
    officialCollectionAbilities := HashMap.HashMap<Nat, Text>(32, natEqual, natHash);
    disabledAbilities := HashMap.HashMap<Text, Bool>(8, Text.equal, textHash);
    gameSubmissions := HashMap.HashMap<Text, GameSubmission>(16, Text.equal, textHash);
    royalties := HashMap.HashMap<Principal, Nat>(16, Principal.equal, Principal.hash);
    nftSellerEarningsE8s := HashMap.HashMap<Principal, Nat>(16, Principal.equal, Principal.hash);
    refundsE8s := HashMap.HashMap<Principal, Nat>(16, Principal.equal, Principal.hash);
    escrows := HashMap.HashMap<Text, EscrowedNft>(16, Text.equal, textHash);
    gameRawTicketPools := HashMap.HashMap<Text, Nat>(16, Text.equal, textHash);
    gameBackedTicketPools := HashMap.HashMap<Text, Nat>(16, Text.equal, textHash);
    paidGameSessions := HashMap.HashMap<Text, PaidGameSession>(16, Text.equal, textHash);
    gamePayoutConfigs := HashMap.HashMap<Text, GamePayoutConfig>(16, Text.equal, textHash);
    gameTicketJackpotConfigs := HashMap.HashMap<Text, GameTicketJackpotConfig>(16, Text.equal, textHash);
    tipReceipts := Buffer.Buffer<TipReceipt>(tipReceiptEntries.size() + 8);
    ticketJackpotWins := Buffer.Buffer<TicketJackpotWin>(ticketJackpotWinEntries.size() + 8);
    ticketJackpotWinDetails := Buffer.Buffer<TicketJackpotWinDetail>(ticketJackpotWinTierEntries.size() + 8);
    claimedSet := HashMap.HashMap<Nat, Bool>(32, natEqual, natHash);
    playLog := Buffer.Buffer<(Principal, Int)>(0);
    dailyTickets := HashMap.HashMap<Principal, (Nat, Int)>(32, Principal.equal, Principal.hash);
    accountPlayCount := HashMap.HashMap<Principal, Nat>(32, Principal.equal, Principal.hash);
    leaderboards := HashMap.HashMap<Text, LeaderboardEntry>(8, Text.equal, textHash);

    // These legacy arrays are non-critical volatile/derived state and are the
    // remaining known upgrade hazard when older stable layouts are restored
    // under enhanced orthogonal persistence. Explicitly resetting them here
    // ensures later lazy hydration never touches incompatible legacy bytes.
    // Keep leaderboardEntries intact: hydrateRuntimeStateIfNeeded() rebuilds
    // the runtime leaderboard map from that stable array after upgrade.
    claimedDeposits := [];
    playLogEntries := [];
    dailyTicketEntries := [];
    accountPlayCountEntries := [];

    runtimeStateHydrated := false;
    // Session #3: rebuild runtime maps immediately (after the legacy-array reset above) instead of
    // waiting for the first update call - otherwise every query between an upgrade and that first
    // update saw empty maps (Ticket games showing as Non-Ticket, blank game details), and a save in
    // that window could overwrite real data with blanks. A failure here fails the upgrade, which
    // rolls back automatically with all saved data intact.
    hydrateRuntimeStateIfNeeded();
  };

  func findPrincipalNat(entries : [(Principal, Nat)], key : Principal) : ?Nat {
    for ((entryKey, entryValue) in entries.vals()) {
      if (Principal.equal(entryKey, key)) {
        return ?entryValue;
      };
    };
    null;
  };

  func findNatNat(entries : [(Nat, Nat)], key : Nat) : ?Nat {
    for ((entryKey, entryValue) in entries.vals()) {
      if (entryKey == key) {
        return ?entryValue;
      };
    };
    null;
  };

  func findNatText(entries : [(Nat, Text)], key : Nat) : ?Text {
    for ((entryKey, entryValue) in entries.vals()) {
      if (entryKey == key) {
        return ?entryValue;
      };
    };
    null;
  };

  func findTextValue<T>(entries : [(Text, T)], key : Text) : ?T {
    for ((entryKey, entryValue) in entries.vals()) {
      if (entryKey == key) {
        return ?entryValue;
      };
    };
    null;
  };

  func nftListingToStable(listing : NftListing) : NftListingStable {
    {
      id = listing.id;
      listingType = listing.listingType;
      name = listing.name;
      description = listing.description;
      rarity = listing.rarity;
      ticketCost = listing.ticketCost;
      imageUrl = listing.imageUrl;
      creator = listing.creator;
      tier = listing.tier;
      status = listing.status;
      feePaid = listing.feePaid;
      showroomFeePaid = listing.showroomFeePaid;
      txId = listing.txId;
      createdAt = listing.createdAt;
      sourceCanisterId = listing.sourceCanisterId;
      sourceTokenId = listing.sourceTokenId;
      collectionName = listing.collectionName;
    }
  };

  func nftListingSourceTokenKeyFallback(stableListing : NftListingStable, savedSourceTokenKey : ?Text) : Text {
    switch (savedSourceTokenKey) {
      case (?key) {
        if (Text.size(key) > 0) {
          return key;
        };
      };
      case null {};
    };

    if (stableListing.sourceTokenId > 0) {
      return Nat.toText(stableListing.sourceTokenId);
    };

    if (stableListing.listingType == "mint") {
      return "";
    };

    // Legacy EXT listings created before sourceTokenKey had no full token key
    // in stable storage. Use deterministic descriptive source metadata rather
    // than failing upgrade; operators can still reconcile these via custody UI.
    if (Text.size(stableListing.sourceCanisterId) > 0 or Text.size(stableListing.imageUrl) > 0) {
      return stableListing.sourceCanisterId # ":" # stableListing.imageUrl;
    };

    stableListing.collectionName
  };

  func hydrateNftListing(listingId : Text, stableListing : NftListingStable) : NftListing {
    let sourceTokenKey = nftListingSourceTokenKeyFallback(stableListing, findTextValue<Text>(nftListingSourceTokenKeyEntries, listingId));
    {
      id = stableListing.id;
      listingType = stableListing.listingType;
      name = stableListing.name;
      description = stableListing.description;
      rarity = stableListing.rarity;
      ticketCost = stableListing.ticketCost;
      imageUrl = stableListing.imageUrl;
      creator = stableListing.creator;
      tier = stableListing.tier;
      status = stableListing.status;
      feePaid = stableListing.feePaid;
      showroomFeePaid = stableListing.showroomFeePaid;
      txId = stableListing.txId;
      createdAt = stableListing.createdAt;
      sourceCanisterId = stableListing.sourceCanisterId;
      sourceTokenId = stableListing.sourceTokenId;
      sourceTokenKey = sourceTokenKey;
      collectionName = stableListing.collectionName;
    }
  };

  func hydrateRuntimeStateIfNeeded() {
    if (runtimeStateHydrated) {
      return;
    };

    tickets := HashMap.fromIter<Principal, Nat>(ticketEntries.vals(), ticketEntries.size(), Principal.equal, Principal.hash);
    gxp := HashMap.fromIter<Principal, Nat>(gxpEntries.vals(), gxpEntries.size(), Principal.equal, Principal.hash);
    dxp := HashMap.fromIter<Principal, Nat>(dxpEntries.vals(), dxpEntries.size(), Principal.equal, Principal.hash);
    mxp := HashMap.fromIter<Principal, Nat>(mxpEntries.vals(), mxpEntries.size(), Principal.equal, Principal.hash);
    playerProfiles := HashMap.fromIter<Principal, PlayerProfile>(playerProfileEntries.vals(), playerProfileEntries.size(), Principal.equal, Principal.hash);
    costs := HashMap.fromIter<Nat, Nat>(costEntries.vals(), costEntries.size(), natEqual, natHash);
    tokens := HashMap.fromIter<Principal, Nat>(tokenEntries.vals(), tokenEntries.size(), Principal.equal, Principal.hash);
    nftListings := HashMap.HashMap<Text, NftListing>(nftListingEntries.size() + 8, Text.equal, textHash);
    for ((listingId, stableListing) in nftListingEntries.vals()) {
      nftListings.put(listingId, hydrateNftListing(listingId, stableListing));
    };
    officialCollections := HashMap.fromIter<Text, OfficialCollection>(officialCollectionEntries.vals(), officialCollectionEntries.size(), Text.equal, textHash);
    officialCollectionAbilities := HashMap.fromIter<Nat, Text>(officialCollectionAbilityEntries.vals(), officialCollectionAbilityEntries.size(), natEqual, natHash);
    disabledAbilities := HashMap.HashMap<Text, Bool>(disabledAbilityEntries.size() + 8, Text.equal, textHash);
    for (ability in disabledAbilityEntries.vals()) {
      disabledAbilities.put(ability, true);
    };
    externalCollections := HashMap.fromIter<Text, Text>(externalCollectionEntries.vals(), externalCollectionEntries.size(), Text.equal, textHash);
    moderators := HashMap.fromIter<Principal, [Text]>(moderatorEntries.vals(), moderatorEntries.size(), Principal.equal, Principal.hash);
    gameSubmissions := HashMap.fromIter<Text, GameSubmission>(gameSubmissionEntries.vals(), gameSubmissionEntries.size(), Text.equal, textHash);
    royalties := HashMap.fromIter<Principal, Nat>(royaltyEntries.vals(), royaltyEntries.size(), Principal.equal, Principal.hash);
    tipEarnings := HashMap.fromIter<Principal, Nat>(tipEarningsEntries.vals(), tipEarningsEntries.size(), Principal.equal, Principal.hash);
    pendingZipUploads := HashMap.fromIter<Text, PendingZipUpload>(pendingZipUploadEntries.vals(), pendingZipUploadEntries.size(), Text.equal, textHash);
    zipChunks := HashMap.fromIter<Text, Blob>(zipChunkEntries.vals(), zipChunkEntries.size(), Text.equal, textHash);
    notifications := HashMap.fromIter<Text, UserNotification>(notificationEntries.vals(), notificationEntries.size(), Text.equal, textHash);
    gameCategories := HashMap.fromIter<Text, Text>(gameCategoryEntries.vals(), gameCategoryEntries.size(), Text.equal, textHash);
    gameAccessibility := HashMap.fromIter<Text, (Bool, Bool, Bool, Bool)>(gameAccessibilityEntries.vals(), gameAccessibilityEntries.size(), Text.equal, textHash);
    gameMonetization := HashMap.fromIter<Text, (Bool, Bool)>(gameMonetizationEntries.vals(), gameMonetizationEntries.size(), Text.equal, textHash);
    gamePricing := HashMap.fromIter<Text, (Nat, Nat)>(gamePricingEntries.vals(), gamePricingEntries.size(), Text.equal, textHash);
    nftSellerEarningsE8s := HashMap.fromIter<Principal, Nat>(nftSellerEarningEntries.vals(), nftSellerEarningEntries.size(), Principal.equal, Principal.hash);
    refundsE8s := HashMap.fromIter<Principal, Nat>(refundEntries.vals(), refundEntries.size(), Principal.equal, Principal.hash);
    escrows := HashMap.fromIter<Text, EscrowedNft>(escrowEntries.vals(), escrowEntries.size(), Text.equal, textHash);
    gameRawTicketPools := HashMap.fromIter<Text, Nat>(gameRawTicketPoolEntries.vals(), gameRawTicketPoolEntries.size(), Text.equal, textHash);
    gameBackedTicketPools := HashMap.fromIter<Text, Nat>(gameBackedTicketPoolEntries.vals(), gameBackedTicketPoolEntries.size(), Text.equal, textHash);
    paidGameSessions := HashMap.fromIter<Text, PaidGameSession>(paidGameSessionEntries.vals(), paidGameSessionEntries.size(), Text.equal, textHash);
    gamePurchases := HashMap.fromIter<Text, Bool>(gamePurchaseEntries.vals(), gamePurchaseEntries.size(), Text.equal, textHash);
    gameTokenSpend := HashMap.fromIter<Text, Nat>(gameTokenSpendEntries.vals(), gameTokenSpendEntries.size(), Text.equal, textHash);
    gamePayoutConfigs := HashMap.fromIter<Text, GamePayoutConfig>(gamePayoutConfigEntries.vals(), gamePayoutConfigEntries.size(), Text.equal, textHash);
    ticketJackpotWins := Buffer.fromArray<TicketJackpotWin>(ticketJackpotWinEntries);
    ticketJackpotWinDetails := Buffer.fromArray<TicketJackpotWinDetail>(ticketJackpotWinTierEntries);
    gameTicketJackpotConfigs := HashMap.fromIter<Text, GameTicketJackpotConfig>(gameTicketJackpotConfigV2Entries.vals(), gameTicketJackpotConfigV2Entries.size(), Text.equal, textHash);
    tipReceipts := Buffer.fromArray<TipReceipt>(tipReceiptEntries);
    for ((gameId, legacyConfig) in gameTicketJackpotConfigEntries.vals()) {
      switch (gameTicketJackpotConfigs.get(gameId)) {
        case null { gameTicketJackpotConfigs.put(gameId, normalizeGameTicketJackpotConfig(legacyConfig)) };
        case (?_) {};
      };
    };
    migrateLegacyGameTicketPoolsIfNeeded();

    claimedSet := HashMap.HashMap<Nat, Bool>(claimedDeposits.size() + 8, natEqual, natHash);
    for (idx in claimedDeposits.vals()) {
      claimedSet.put(idx, true);
    };

    playLog := Buffer.fromArray<(Principal, Int)>(playLogEntries);
    dailyTickets := HashMap.HashMap<Principal, (Nat, Int)>(dailyTicketEntries.size() + 8, Principal.equal, Principal.hash);
    for ((player, earned, day) in dailyTicketEntries.vals()) {
      dailyTickets.put(player, (earned, day));
    };
    accountPlayCount := HashMap.fromIter<Principal, Nat>(accountPlayCountEntries.vals(), accountPlayCountEntries.size(), Principal.equal, Principal.hash);
    leaderboards := HashMap.fromIter<Text, LeaderboardEntry>(leaderboardEntries.vals(), leaderboardEntries.size(), Text.equal, textHash);
    playerBests := HashMap.fromIter<Principal, [(Text, Nat, Int)]>(playerBestEntries.vals(), playerBestEntries.size(), Principal.equal, Principal.hash);
    profileWalls := HashMap.fromIter<Principal, [Text]>(profileWallEntries.vals(), profileWallEntries.size(), Principal.equal, Principal.hash);
    runtimeStateHydrated := true;
  };

  // === HELPERS ===
  func isModerator(caller : Principal) : Bool {
    hydrateRuntimeStateIfNeeded();
    moderators.get(caller) != null;
  };

  func isAdmin(caller : Principal) : Bool {
    for (a in ADMINS.vals()) {
      if (Principal.equal(caller, a)) return true;
    };
    Principal.equal(caller, JAY_PRINCIPAL);
  };

  public query func isAdminPrincipal(principal : Principal) : async Bool {
    isAdmin(principal);
  };

  func getCost(tokenId : TokenId) : Nat {
    if (runtimeStateHydrated) {
      switch (costs.get(tokenId)) { case null defaultCost; case (?v) v };
    } else {
      switch (findNatNat(costEntries, tokenId)) { case null defaultCost; case (?v) v };
    };
  };

  func getTicketBalance(player : Principal) : Nat {
    if (runtimeStateHydrated) {
      switch (tickets.get(player)) { case null 0; case (?v) v };
    } else {
      switch (findPrincipalNat(ticketEntries, player)) { case null 0; case (?v) v };
    };
  };

  func getGxpBalance(player : Principal) : Nat {
    if (runtimeStateHydrated) {
      switch (gxp.get(player)) { case null 0; case (?v) v };
    } else {
      switch (findPrincipalNat(gxpEntries, player)) { case null 0; case (?v) v };
    };
  };

  // Soulbound: only ever adds, never subtracts or resets. Tracks the site-wide max as it goes.
  func addGxp(player : Principal, amount : Nat) {
    if (amount == 0) return;
    let newGxp = getGxpBalance(player) + amount * (100 + 5 * abilityCountOf(player, "gxp-amp")) / 100;
    gxp.put(player, newGxp);
    if (newGxp > maxGxpEverSeen) { maxGxpEverSeen := newGxp };
  };

  func getDxpBalance(player : Principal) : Nat {
    if (runtimeStateHydrated) {
      switch (dxp.get(player)) { case null 0; case (?v) v };
    } else {
      switch (findPrincipalNat(dxpEntries, player)) { case null 0; case (?v) v };
    };
  };

  func addDxp(player : Principal, amount : Nat) {
    if (amount == 0) return;
    let newDxp = getDxpBalance(player) + amount * (100 + 5 * abilityCountOf(player, "dxp-amp")) / 100;
    dxp.put(player, newDxp);
    if (newDxp > maxDxpEverSeen) { maxDxpEverSeen := newDxp };
  };

  func getMxpBalance(player : Principal) : Nat {
    if (runtimeStateHydrated) {
      switch (mxp.get(player)) { case null 0; case (?v) v };
    } else {
      switch (findPrincipalNat(mxpEntries, player)) { case null 0; case (?v) v };
    };
  };

  func addMxp(player : Principal, amount : Nat) {
    if (amount == 0) return;
    let newMxp = getMxpBalance(player) + amount * (100 + 5 * abilityCountOf(player, "mxp-amp")) / 100;
    mxp.put(player, newMxp);
    if (newMxp > maxMxpEverSeen) { maxMxpEverSeen := newMxp };
  };

  func getTokenBalance(player : Principal) : Nat {
    if (runtimeStateHydrated) {
      switch (tokens.get(player)) { case null 0; case (?v) v };
    } else {
      switch (findPrincipalNat(tokenEntries, player)) { case null 0; case (?v) v };
    };
  };

  func getRoyaltyBalance(creator : Principal) : Nat {
    getGameCreatorEarningsBalance(creator);
  };

  func getGameCreatorEarningsBalance(creator : Principal) : Nat {
    if (runtimeStateHydrated) {
      switch (royalties.get(creator)) { case null 0; case (?v) v };
    } else {
      switch (findPrincipalNat(royaltyEntries, creator)) { case null 0; case (?v) v };
    };
  };

  func getNftSellerEarningsBalance(seller : Principal) : Nat {
    if (runtimeStateHydrated) {
      switch (nftSellerEarningsE8s.get(seller)) { case null 0; case (?v) v };
    } else {
      switch (findPrincipalNat(nftSellerEarningEntries, seller)) { case null 0; case (?v) v };
    };
  };

  func paidGameSessionKey(player : Principal, gameId : Text) : Text {
    Principal.toText(player) # "::" # gameId;
  };

  // Permanent ownership record for outright-purchased games (see purchaseGame below). Same
  // per-(player,game) composite key convention as paidGameSessionKey. Once true, always true -
  // there's no revoke path, since a purchase is meant to be permanent.
  func gamePurchaseKey(player : Principal, gameId : Text) : Text {
    Principal.toText(player) # "::" # gameId;
  };

  // Every game session (a ticket run or a non-ticket visit) lasts at most 2 hours; older ones count as expired.
  transient let SESSION_MAX_NS : Int = 7_200_000_000_000;
  func getOpenPaidGameSession(player : Principal, gameId : Text) : ?PaidGameSession {
    switch (paidGameSessions.get(paidGameSessionKey(player, gameId))) {
      case null null;
      case (?session) { if (session.open and Time.now() - session.openedAt < SESSION_MAX_NS) ?session else null };
    };
  };

  // Paid session start is the only token deduction for a paid game play.
  // Score submission only finalizes an already-paid session and may pay tickets.
  func openPaidGameSession(player : Principal, gameId : Text, tokenCost : Nat) {
    paidGameSessions.put(paidGameSessionKey(player, gameId), {
      player = player;
      gameId = gameId;
      tokenCost = tokenCost;
      openedAt = Time.now();
      open = true;
    });
  };

  func closePaidGameSession(player : Principal, gameId : Text) {
    let key = paidGameSessionKey(player, gameId);
    switch (paidGameSessions.get(key)) {
      case null {};
      case (?session) {
        paidGameSessions.put(key, {
          player = session.player;
          gameId = session.gameId;
          tokenCost = session.tokenCost;
          openedAt = session.openedAt;
          open = false;
        });
      };
    };
  };

  func restoreRoyaltyBalance(creator : Principal, amountE8s : Nat) {
    restoreGameCreatorEarningsBalance(creator, amountE8s);
  };

  func restoreGameCreatorEarningsBalance(creator : Principal, amountE8s : Nat) {
    let current = getGameCreatorEarningsBalance(creator);
    royalties.put(creator, current + amountE8s);
  };

  func getTipEarningsBalance(creator : Principal) : Nat {
    if (runtimeStateHydrated) {
      switch (tipEarnings.get(creator)) { case null 0; case (?v) v };
    } else {
      switch (findPrincipalNat(tipEarningsEntries, creator)) { case null 0; case (?v) v };
    };
  };

  func restoreTipEarningsBalance(creator : Principal, amountE8s : Nat) {
    let current = getTipEarningsBalance(creator);
    tipEarnings.put(creator, current + amountE8s);
  };

  func restoreNftSellerEarningsBalance(seller : Principal, amountE8s : Nat) {
    let current = getNftSellerEarningsBalance(seller);
    nftSellerEarningsE8s.put(seller, current + amountE8s);
  };

  func creditNftSellerEarnings(seller : Principal, amountE8s : Nat) : Nat {
    let current = getNftSellerEarningsBalance(seller);
    let newBal = current + amountE8s;
    nftSellerEarningsE8s.put(seller, newBal);
    newBal;
  };

  func getRefundBalance(creator : Principal) : Nat {
    if (runtimeStateHydrated) {
      switch (refundsE8s.get(creator)) { case null 0; case (?v) v };
    } else {
      switch (findPrincipalNat(refundEntries, creator)) { case null 0; case (?v) v };
    };
  };

  func restoreRefundBalance(creator : Principal, amountE8s : Nat) {
    let current = getRefundBalance(creator);
    refundsE8s.put(creator, current + amountE8s);
  };

  func getGameRawTicketPoolValue(gameId : Text) : Nat {
    if (runtimeStateHydrated) {
      switch (gameRawTicketPools.get(gameId)) { case null 0; case (?value) value };
    } else {
      switch (findTextValue<Nat>(gameRawTicketPoolEntries, gameId)) { case null 0; case (?value) value };
    };
  };

  func setGameRawTicketPoolValue(gameId : Text, value : Nat) {
    gameRawTicketPools.put(gameId, value);
  };

  func addToGameRawTicketPool(gameId : Text, amount : Nat) {
    setGameRawTicketPoolValue(gameId, getGameRawTicketPoolValue(gameId) + amount);
  };

  func getGameBackedTicketPoolValue(gameId : Text) : Nat {
    if (runtimeStateHydrated) {
      switch (gameBackedTicketPools.get(gameId)) { case null 0; case (?value) value };
    } else {
      switch (findTextValue<Nat>(gameBackedTicketPoolEntries, gameId)) { case null 0; case (?value) value };
    };
  };

  func setGameBackedTicketPoolValue(gameId : Text, value : Nat) {
    gameBackedTicketPools.put(gameId, value);
  };

  func addToGameBackedTicketPool(gameId : Text, amount : Nat) {
    setGameBackedTicketPoolValue(gameId, getGameBackedTicketPoolValue(gameId) + amount);
  };

  func isBlankText(value : Text) : Bool {
    Text.size(value) == 0;
  };

  func isTicketGameTier(gameTier : Text) : Bool {
    gameTier == "showroom" or gameTier == "jays-picks";
  };

  // Real, authoritative source of ticket-pool eligibility - the creator's own explicit choice via
  // setGameMonetization above, not the game's tier. Replaces the old pure-tier rule entirely (no
  // fallback to isTicketGameTier for games with no entry - they simply default to false, i.e. not
  // ticket-backed, per Jay's explicit call not to preserve old tier-implied behavior).
  func isTicketGameSubmission(game : GameSubmission) : Bool {
    switch (gameMonetization.get(game.id)) {
      case (?(paysTickets, _)) paysTickets;
      case null false;
    };
  };

  func clampBackedPoolToRaw(gameId : Text) {
    let rawPool = getGameRawTicketPoolValue(gameId);
    let backedPool = getGameBackedTicketPoolValue(gameId);
    if (backedPool > rawPool) {
      setGameBackedTicketPoolValue(gameId, rawPool);
    };
  };

  func getTicketReserveAuditSnapshot() : TicketReserveAuditSnapshot {
    var totalRawTicketPool : Nat = 0;
    var totalBackedTicketPool : Nat = 0;
    var ticketGameCount : Nat = 0;

    if (runtimeStateHydrated) {
      for ((gameId, game) in gameSubmissions.entries()) {
        if (game.status == "live" and isTicketGameSubmission(game)) {
          ticketGameCount += 1;
          totalRawTicketPool += getGameRawTicketPoolValue(gameId);
          totalBackedTicketPool += getGameBackedTicketPoolValue(gameId);
        };
      };
    } else {
      for ((gameId, game) in gameSubmissionEntries.vals()) {
        if (game.status == "live" and isTicketGameSubmission(game)) {
          ticketGameCount += 1;
          totalRawTicketPool += getGameRawTicketPoolValue(gameId);
          totalBackedTicketPool += getGameBackedTicketPoolValue(gameId);
        };
      };
    };

    let outstandingBackedLiability = totalBackedTicketPool;
    let coverageGap = if (outstandingBackedLiability > totalRawTicketPool) outstandingBackedLiability - totalRawTicketPool else 0;
    let surplusBacking = if (totalRawTicketPool > outstandingBackedLiability) totalRawTicketPool - outstandingBackedLiability else 0;
    let unbackedRawExposure = if (totalRawTicketPool > totalBackedTicketPool) totalRawTicketPool - totalBackedTicketPool else 0;

    {
      totalRawTicketPool = totalRawTicketPool;
      totalBackedTicketPool = totalBackedTicketPool;
      outstandingBackedLiability = outstandingBackedLiability;
      coverageGap = coverageGap;
      surplusBacking = surplusBacking;
      unbackedRawExposure = unbackedRawExposure;
      ticketGameCount = ticketGameCount;
    };
  };

  func totalOutstandingTokens() : Nat {
    var total : Nat = 0;
    if (runtimeStateHydrated) {
      for ((_owner, amount) in tokens.entries()) {
        total += amount;
      };
    } else {
      for ((_owner, amount) in tokenEntries.vals()) {
        total += amount;
      };
    };
    total;
  };

  func totalOutstandingTickets() : Nat {
    var total : Nat = 0;
    if (runtimeStateHydrated) {
      for (entry in tickets.entries()) {
        let amount = entry.1;
        total += amount;
      };
    } else {
      for (entry in ticketEntries.vals()) {
        let amount = entry.1;
        total += amount;
      };
    };
    total;
  };

  func totalGameCreatorEarningsLiabilityE8s() : Nat {
    var total : Nat = 0;
    if (runtimeStateHydrated) {
      for ((_creator, amount) in royalties.entries()) {
        total += amount;
      };
    } else {
      for ((_creator, amount) in royaltyEntries.vals()) {
        total += amount;
      };
    };
    total;
  };

  func totalNftSellerEarningsLiabilityE8s() : Nat {
    var total : Nat = 0;
    if (runtimeStateHydrated) {
      for ((_seller, amount) in nftSellerEarningsE8s.entries()) {
        total += amount;
      };
    } else {
      for ((_seller, amount) in nftSellerEarningEntries.vals()) {
        total += amount;
      };
    };
    total;
  };

  func totalRoyaltyLiabilityE8s() : Nat {
    // Legacy-compatible treasury field: combined claimable creator/seller earnings liability.
    totalGameCreatorEarningsLiabilityE8s() + totalNftSellerEarningsLiabilityE8s();
  };

  func totalRefundLiabilityE8s() : Nat {
    var total : Nat = 0;
    if (runtimeStateHydrated) {
      for ((_creator, amount) in refundsE8s.entries()) {
        total += amount;
      };
    } else {
      for ((_creator, amount) in refundEntries.vals()) {
        total += amount;
      };
    };
    total;
  };

  func totalBackedTicketPoolReserve() : Nat {
    getTicketReserveAuditSnapshot().totalBackedTicketPool;
  };

  public shared(_msg) func getTreasuryBalance() : async TreasuryBalanceSnapshot {
    let selfPrincipal = Principal.fromActor(ArcadeBackend);
    let actualBalanceE8s = await ICP_LEDGER_ICRC1.icrc1_balance_of({ owner = selfPrincipal; subaccount = null });
    let outstandingTokens = totalOutstandingTokens();
    let backedTicketPoolTickets = totalBackedTicketPoolReserve();
    let tokenLiabilityE8s = totalOutstandingTokens() * TOKEN_LIABILITY_E8S;
    let royaltyLiabilityE8s = totalRoyaltyLiabilityE8s();
    let refundLiabilityE8s = totalRefundLiabilityE8s();
    let ticketPoolLiabilityE8s = totalBackedTicketPoolReserve() * TICKET_LIABILITY_E8S;
    let ticketHolderLiabilityE8s = totalOutstandingTickets() * TICKET_LIABILITY_E8S;
    let reservedE8s = tokenLiabilityE8s + royaltyLiabilityE8s + refundLiabilityE8s + ticketPoolLiabilityE8s + ticketHolderLiabilityE8s;
    let protectedE8s = reservedE8s + TREASURY_SAFETY_BUFFER_E8S;
    let withdrawableE8s = if (actualBalanceE8s > protectedE8s) actualBalanceE8s - protectedE8s else 0;
    {
      balanceE8s = actualBalanceE8s;
      reservedE8s = reservedE8s;
      outstandingTokens = outstandingTokens;
      withdrawableE8s = withdrawableE8s;
      tokenLiabilityE8s = tokenLiabilityE8s;
      royaltyLiabilityE8s = royaltyLiabilityE8s;
      refundLiabilityE8s = refundLiabilityE8s;
      ticketPoolLiabilityE8s = ticketPoolLiabilityE8s;
      ticketHolderLiabilityE8s = ticketHolderLiabilityE8s;
      backedTicketPoolTickets = backedTicketPoolTickets;
      safetyBufferE8s = TREASURY_SAFETY_BUFFER_E8S;
    };
  };

  public shared(_msg) func getTreasuryLaneSnapshot() : async TreasuryLaneSnapshot {
    let selfPrincipal = Principal.fromActor(ArcadeBackend);
    let treasury = await getTreasuryBalance();
    let operatingBalanceE8s = await ICP_LEDGER_ICRC1.icrc1_balance_of({ owner = selfPrincipal; subaccount = ?OPERATING_TREASURY_SUBACCOUNT });
    {
      protectedAccountId = SELF_ACCOUNT_ID;
      operatingAccountId = OPERATING_TREASURY_ACCOUNT_ID;
      protectedBalanceE8s = treasury.balanceE8s;
      operatingBalanceE8s = operatingBalanceE8s;
      backendSafeWithdrawableE8s = treasury.withdrawableE8s;
      protectedReservedE8s = treasury.reservedE8s;
      operatingIncludedInBacking = false;
      operatingIncludedInBackendSafeMath = false;
    };
  };

  func migrateLegacyGameTicketPoolsIfNeeded() {
    let migratedRawPools = HashMap.HashMap<Text, Nat>(gameRawTicketPoolEntries.size() + 8, Text.equal, textHash);
    let migratedBackedPools = HashMap.HashMap<Text, Nat>(gameBackedTicketPoolEntries.size() + 8, Text.equal, textHash);

    // Session #3 fix: keep EVERY pool. The old filter (live Ticket games only) silently erased the pool of
    // any suspended / pending / monetization-less game on every upgrade - real ICP-backed value.
    for ((gameId, rawPool) in gameRawTicketPoolEntries.vals()) {
      migratedRawPools.put(gameId, rawPool);
    };

    // Public/backed truth is one-way explicit. Never infer backed balances from
    // legacy raw counters, because that would leak pre-separation state into the
    // public liability surface after upgrade.
    for ((gameId, backedPool) in gameBackedTicketPoolEntries.vals()) {
      let rawPool = switch (migratedRawPools.get(gameId)) { case (?value) value; case null 0 };
      let sanitizedBackedPool = if (backedPool > rawPool) rawPool else backedPool;
      migratedBackedPools.put(gameId, sanitizedBackedPool);
    };

    gameRawTicketPools := migratedRawPools;
    gameBackedTicketPools := migratedBackedPools;
    gameRawTicketPoolEntries := [];
    gameBackedTicketPoolEntries := [];
  };

  func computeTicketGamePoolCredit(amount : Nat) : Nat {
    // Model A funding pass: align gameplay-funded pool growth with the published
    // fixed funding lane semantics of 1 ICP = 1000 tickets and 1 ICP = 100 tokens.
    // Ticket-game gameplay spends route only the published pool lane into explicit
    // ticket credit: 80% of the ICP-equivalent lane, or 8 tickets per token at the
    // fixed 1 ICP = 100 tokens / 1000 tickets semantics. Raw and backed stay
    // mirrored on funding, while payouts still drain only the backed/public side.
    (amount * 10 * TICKET_GAME_POOL_SHARE) / 100;
  };

  func logRevenue(eventType : Text, amount : Nat, from : Principal, memo : Nat) {
    let log = Buffer.fromArray<RevenueEvent>(revenueLogEntries);
    log.add({
      eventType = eventType;
      amount = amount;
      from = from;
      memo = memo;
      timestamp = Time.now();
    });
    revenueLogEntries := Buffer.toArray(log);
    totalRevenueE8s += amount;
  };

  func genListingId(prefix : Text) : Text {
    nftListingCounter += 1;
    prefix # "-" # Nat.toText(nftListingCounter) # "-" # Int.toText(Time.now());
  };

  func genOfficialCollectionId() : Text {
    officialCollectionCounter += 1;
    "official-" # Nat.toText(officialCollectionCounter) # "-" # Int.toText(Time.now());
  };

  func collectionContainsToken(collection : OfficialCollection, tokenId : Nat) : Bool {
    for (existingId in collection.nftIds.vals()) {
      if (existingId == tokenId) return true;
    };
    false;
  };

  func tokenBelongsToOfficialCollection(tokenId : Nat) : Bool {
    let cols = if (runtimeStateHydrated) { Iter.toArray(officialCollections.vals()) } else { Array.map<(Text, OfficialCollection), OfficialCollection>(officialCollectionEntries, func((_id, col)) { col }) };
    for (collection in cols.vals()) {
      if (collectionContainsToken(collection, tokenId)) return true;
    };
    false;
  };

  func collectionAbilitiesForIds(nftIds : [Nat]) : [(Text, Text)] {
    let abilityEntries = if (runtimeStateHydrated) { Iter.toArray(officialCollectionAbilities.entries()) } else { officialCollectionAbilityEntries };
    let buf = Buffer.Buffer<(Text, Text)>(nftIds.size());
    for (tokenId in nftIds.vals()) {
      for ((abilityTokenId, ability) in abilityEntries.vals()) {
        if (abilityTokenId == tokenId) {
          buf.add((Nat.toText(tokenId), ability));
        };
      };
    };
    Buffer.toArray(buf);
  };

  func withFreshCollectionAbilities(collection : OfficialCollection) : OfficialCollection {
    {
      id = collection.id;
      name = collection.name;
      description = collection.description;
      creator = collection.creator;
      imageUrls = collection.imageUrls;
      nftIds = collection.nftIds;
      ticketCost = collection.ticketCost;
      totalSupply = collection.totalSupply;
      abilities = []; // secret: never derive per-NFT abilities into public collection data
      createdAt = collection.createdAt;
    }
  };

  func putOfficialCollection(collection : OfficialCollection) {
    officialCollections.put(collection.id, withFreshCollectionAbilities(collection));
  };

  func genGameId() : Text {
    gameSubmissionCounter += 1;
    "game-" # Nat.toText(gameSubmissionCounter) # "-" # Int.toText(Time.now());
  };

  func chargeNftListingFee(caller : Principal) : Result.Result<(), Text> {
    if (isAdmin(caller)) return #ok(());
    let balance = getTokenBalance(caller);
    if (balance < NFT_LISTING_FEE_TOKENS) {
      return #err("Not enough tokens. Listing an NFT costs " # Nat.toText(NFT_LISTING_FEE_TOKENS) # " Tokens. Have " # Nat.toText(balance));
    };
    tokens.put(caller, balance - NFT_LISTING_FEE_TOKENS);
    // NFT listing fee -> Prize Booth arcade share (was previously left unassigned)
    prizeBoothArcadeShareE8s += NFT_LISTING_FEE_TOKENS * TOKEN_LIABILITY_E8S;
    #ok(());
  };

  // ============================================
  // === TOKEN BALANCES (Arcade Tokens) ===
  // ============================================

  // Track claimed deposit block indexes (prevent double-credit)
  stable var claimedDeposits : [Nat] = [];
  transient var claimedSet = HashMap.HashMap<Nat, Bool>(32, natEqual, natHash);

  /// Credit tokens after ICP deposit (admin only)
  public shared(msg) func creditTokens(player : Principal, amount : Nat) : async Result.Result<Nat, Text> {
    assert (not isBannedNow(msg.caller)); // banned: only withdrawals, claims and listing allowed
    if (not ALLOW_TEST_MINTING) return #err("Test minting is disabled on this network");
    if (not isAdmin(msg.caller)) return #err("Not authorized");
    hydrateRuntimeStateIfNeeded();
    let current = getTokenBalance(player);
    let newBal = current + amount;
    tokens.put(player, newBal);
    #ok(newBal);
  };

  /// Legacy deposit-by-block-index entrypoint is intentionally disabled.
  /// It previously trusted caller-provided block data and could mint Tokens without ledger verification.
  /// Use convertDepositToTokens(), which checks the caller's canister-owned ICP subaccount and moves funds first.
  public shared(_msg) func deposit(_icpE8s : Nat, _blockIndex : Nat) : async Result.Result<Nat, Text> {
    #err("Legacy deposit path disabled. Use convertDepositToTokens after funding your arcade deposit.")
  };

  /// Spend tokens to play a game (no revenue share — legacy/generic)
  public shared(msg) func spendTokens(amount : Nat) : async Result.Result<Nat, Text> {
    assert (not isBannedNow(msg.caller)); // banned: only withdrawals, claims and listing allowed
    if (true) return #err("Retired: token spends go through game play, purchases or tips");
    let caller = msg.caller;
    if (Principal.isAnonymous(caller)) return #err("Must be authenticated");
    hydrateRuntimeStateIfNeeded();
    let balance = getTokenBalance(caller);
    if (balance < amount) return #err("Not enough tokens. Have " # Nat.toText(balance) # " need " # Nat.toText(amount));
    let newBal = balance - amount;
    tokens.put(caller, newBal);
    #ok(newBal);
  };

  /// Spend tokens on a Showroom game and write explicit Model A ticket accounting.
  /// tokenValue = ICP value in e8s of the tokens spent (amount * 1_000_000 for 1:100 ratio)
  public shared(msg) func spendTokensOnGame(amount : Nat, gameId : Text) : async Result.Result<Nat, Text> {
    assert (not isBannedNow(msg.caller)); // banned: only withdrawals, claims and listing allowed
    let caller = msg.caller;
    if (Principal.isAnonymous(caller)) return #err("Must be authenticated");
    hydrateRuntimeStateIfNeeded();
    if (amount == 0) return #err("Amount must be greater than zero");
    if (isBlankText(gameId)) return #err("Game ID is required");
    if (amount != 1) return #err("Every game costs 1 Token per play. Refresh the page and try again.");
    switch (getOpenPaidGameSession(caller, gameId)) {
      case (?_) {
        // Ticket games: one paid play = one run, so paying again starts a new run and forfeits an
        // unsubmitted previous one. Non-ticket games: the open session is the player's visit (resume).
        let ticketRun = switch (gameSubmissions.get(gameId)) { case (?g0) isTicketGameSubmission(g0); case null false };
        if (ticketRun) { closePaidGameSession(caller, gameId) } else { return #err("Session already open") };
      };
      case null {};
    };
    let balance = getTokenBalance(caller);
    if (balance < amount) return #err("Not enough tokens. Have " # Nat.toText(balance) # " need " # Nat.toText(amount));

    switch (gameSubmissions.get(gameId)) {
      case null { return #err("Game not found: " # gameId) };
      case (?game) {
        if (not isTicketGameSubmission(game) and gamePurchases.get(gamePurchaseKey(caller, gameId)) == ?true) {
          return #err("You own this game - it's free to play");
        };
        let newBal = balance - amount;
        tokens.put(caller, newBal);
        addGxp(caller, amount * 10);

        let isTicketGame = isTicketGameSubmission(game);
        if (isTicketGame) {
          // Ticket games now write both sides explicitly. Raw is the internal admin
          // counter; backed is the public payout budget enforced by submitGameScore().
          let ticketPoolCredit = computeTicketGamePoolCredit(amount);
          addToGameRawTicketPool(gameId, ticketPoolCredit);
          addToGameBackedTicketPool(gameId, ticketPoolCredit);
          clampBackedPoolToRaw(gameId);
        };

        // Economy v6 three-way split: creator / arcade (per-type accumulator) / DAO (unified pool).
        // No ICP actually moves here - it already sits in the canister's general custody the
        // moment a deposit became Tokens. These are plain internal Nat counters that later
        // become real icrc1_transfer payouts on claim/withdraw (creator via claimRoyalties,
        // arcade via adminWithdraw*ArcadeShare, DAO via the future lottery system only).
        let icpValueE8s : Nat = amount * 1_000_000;
        let creatorShare = if (isTicketGame) TICKET_GAME_CREATOR_SHARE else REGULAR_GAME_CREATOR_SHARE;
        let arcadeShare = if (isTicketGame) TICKET_GAME_ARCADE_SHARE else REGULAR_GAME_ARCADE_SHARE;
        let daoShare = if (isTicketGame) TICKET_GAME_DAO_SHARE else REGULAR_GAME_DAO_SHARE;
        let creatorShareE8s : Nat = (icpValueE8s * creatorShare) / 100;
        let arcadeShareE8s : Nat = (icpValueE8s * arcadeShare) / 100;
        let daoShareE8s : Nat = (icpValueE8s * daoShare) / 100;
        let currentRoyalty = getRoyaltyBalance(game.creator);
        royalties.put(game.creator, currentRoyalty + creatorShareE8s);
        if (isTicketGame) {
          showroomTicketArcadeShareE8s += arcadeShareE8s;
        } else {
          showroomNonTicketArcadeShareE8s += arcadeShareE8s;
        };
        daoTreasuryE8s += daoShareE8s;
        daoInGamesE8s += daoShareE8s;

        // Auto-unlock: a non-ticket game's cumulative per-play spend (already fully accounted for
        // above via the normal per-play split - no separate transaction here) can reach its
        // purchasePrice on its own, granting the same permanent ownership purchaseGame's explicit
        // Buy button does. Ticket games are excluded since they can never carry a purchasePrice at
        // all (setGameMonetization's own reject rule already guarantees this).
        if (not isTicketGame) {
          let purchasePrice = switch (gamePricing.get(gameId)) {
            case (?(_, pp)) pp;
            case null 0;
          };
          if (purchasePrice > 0) {
            let key = gamePurchaseKey(caller, gameId);
            if (gamePurchases.get(key) != ?true) {
              let priorSpend = switch (gameTokenSpend.get(key)) { case (?s) s; case null 0 };
              let newSpend = priorSpend + amount;
              gameTokenSpend.put(key, newSpend);
              if (newSpend >= purchasePrice) {
                gamePurchases.put(key, true);
              };
            };
          };
        };

        logRevenue("gameplay", icpValueE8s, caller, 3);
        openPaidGameSession(caller, gameId, amount);
        #ok(newBal);
      };
    };
  };

  /// Outright-purchase a non-ticket game for permanent access, per Jay's design: only ever
  /// available for a game the creator explicitly marked Purchasable (wantsPurchasable), never a
  /// ticket game - enforced here server-side regardless of what the frontend allows, same as
  /// setGameMonetization's own reject rule. Once purchased, ownership is permanent (no revoke
  /// path) and checkable via hasGameAccess, so the frontend can skip the coin gate on
  /// future visits. Applies the same 50/30/20 creator/arcade/DAO split as non-ticket per-play
  /// spend (creator to royalties, DAO to daoTreasuryE8s), but credits the arcade share to its own
  /// dedicated showroomPurchaseArcadeShareE8s accumulator, separate from per-play revenue.
  public shared(msg) func purchaseGame(gameId : Text) : async Result.Result<{ tokenBalance : Nat }, Text> {
    assert (not isBannedNow(msg.caller)); // banned: only withdrawals, claims and listing allowed
    let caller = msg.caller;
    if (Principal.isAnonymous(caller)) return #err("Must be authenticated");
    hydrateRuntimeStateIfNeeded();
    let game = switch (gameSubmissions.get(gameId)) {
      case null return #err("Game not found: " # gameId);
      case (?g) g;
    };
    if (isTicketGameSubmission(game)) return #err("Ticket games cannot be purchased outright");
    let purchasePrice = switch (gamePricing.get(gameId)) {
      case (?(_, pp)) pp;
      case null 0;
    };
    if (purchasePrice == 0) return #err("This game is not purchasable");
    let key = gamePurchaseKey(caller, gameId);
    if (gamePurchases.get(key) == ?true) return #err("You already own this game");
    let balance = getTokenBalance(caller);
    if (balance < purchasePrice) return #err("Not enough tokens. Have " # Nat.toText(balance) # " need " # Nat.toText(purchasePrice));

    let newBal = balance - purchasePrice;
    tokens.put(caller, newBal);
    addGxp(caller, purchasePrice * 10);
    gamePurchases.put(key, true);

    let icpValueE8s : Nat = purchasePrice * 1_000_000;
    let creatorShareE8s : Nat = (icpValueE8s * REGULAR_GAME_CREATOR_SHARE) / 100;
    let arcadeShareE8s : Nat = (icpValueE8s * REGULAR_GAME_ARCADE_SHARE) / 100;
    let daoShareE8s : Nat = (icpValueE8s * REGULAR_GAME_DAO_SHARE) / 100;
    let currentRoyalty = getRoyaltyBalance(game.creator);
    royalties.put(game.creator, currentRoyalty + creatorShareE8s);
    showroomPurchaseArcadeShareE8s += arcadeShareE8s;
    daoTreasuryE8s += daoShareE8s;
    daoInGamesE8s += daoShareE8s;

    logRevenue("game-purchase", icpValueE8s, caller, 6);
    #ok({ tokenBalance = newBal });
  };

  // Matches the frontend's already-built expectation of these two names/signatures exactly
  // (an explicit player principal, not the caller) - the Coin Gate screen calls both to show
  // "YOU OWN THIS GAME" and the auto-unlock progress bar.
  public query func hasGameAccess(player : Principal, gameId : Text) : async Bool {
    gamePurchases.get(gamePurchaseKey(player, gameId)) == ?true;
  };

  /// Fixed-cost, time-limited demo for a non-ticket, purchasable game - same non-ticket-only gate
  /// the frontend already applies before ever showing the Try button (purchasePrice>0, not a ticket
  /// game), enforced here server-side too. Counts toward auto-unlock exactly like a normal play
  /// (same 50/30/20 split, same cumulative-spend tracking) since it's just a 1-token play under the
  /// hood, not a separate economic event - the only difference is the fixed demoSeconds window the
  /// frontend uses to time-limit the loaded game.
  public shared(msg) func tryGame(gameId : Text) : async Result.Result<{ tokenBalance : Nat; demoSeconds : Nat }, Text> {
    assert (not isBannedNow(msg.caller)); // banned: only withdrawals, claims and listing allowed
    if (true) return #err("Demo tries have been retired");
    let caller = msg.caller;
    if (Principal.isAnonymous(caller)) return #err("Must be authenticated");
    hydrateRuntimeStateIfNeeded();
    let game = switch (gameSubmissions.get(gameId)) {
      case null return #err("Game not found: " # gameId);
      case (?g) g;
    };
    if (isTicketGameSubmission(game)) return #err("Ticket games don't support demo tries");
    let purchasePrice = switch (gamePricing.get(gameId)) {
      case (?(_, pp)) pp;
      case null 0;
    };
    if (purchasePrice == 0) return #err("This game doesn't support demo tries");
    let key = gamePurchaseKey(caller, gameId);
    if (gamePurchases.get(key) == ?true) return #err("You already own this game");
    let demoCost = 1;
    let balance = getTokenBalance(caller);
    if (balance < demoCost) return #err("Not enough tokens for the demo. Have " # Nat.toText(balance));

    let newBal = balance - demoCost;
    tokens.put(caller, newBal);
    addGxp(caller, demoCost * 10);

    let icpValueE8s : Nat = demoCost * 1_000_000;
    let creatorShareE8s : Nat = (icpValueE8s * REGULAR_GAME_CREATOR_SHARE) / 100;
    let arcadeShareE8s : Nat = (icpValueE8s * REGULAR_GAME_ARCADE_SHARE) / 100;
    let daoShareE8s : Nat = (icpValueE8s * REGULAR_GAME_DAO_SHARE) / 100;
    let currentRoyalty = getRoyaltyBalance(game.creator);
    royalties.put(game.creator, currentRoyalty + creatorShareE8s);
    showroomNonTicketArcadeShareE8s += arcadeShareE8s;
    daoTreasuryE8s += daoShareE8s;
    daoInGamesE8s += daoShareE8s;

    let priorSpend = switch (gameTokenSpend.get(key)) { case (?s) s; case null 0 };
    let newSpend = priorSpend + demoCost;
    gameTokenSpend.put(key, newSpend);
    if (newSpend >= purchasePrice) {
      gamePurchases.put(key, true);
    };

    logRevenue("game-demo", icpValueE8s, caller, 7);
    #ok({ tokenBalance = newBal; demoSeconds = 300 });
  };

  public query func getGameTokenSpend(player : Principal, gameId : Text) : async Nat {
    switch (gameTokenSpend.get(gamePurchaseKey(player, gameId))) {
      case (?s) s;
      case null 0;
    };
  };

  /// Win tickets from a game
  public shared(msg) func winTickets(amount : Nat) : async Result.Result<Nat, Text> {
    assert (not isBannedNow(msg.caller)); // banned: only withdrawals, claims and listing allowed
    if (not ALLOW_TEST_MINTING) return #err("Test minting is disabled on this network");
    // Only callable by admin or the game canister in the future
    if (not isAdmin(msg.caller)) return #err("Not authorized — game payout must be admin-verified");
    hydrateRuntimeStateIfNeeded();
    let caller = msg.caller; // Will be changed to accept player param
    let current = getTicketBalance(caller);
    let newBal = current + amount;
    tickets.put(caller, newBal);
    #ok(newBal);
  };

  // ============================================
  // === ANTI-BOT GAME FRAMEWORK ===
  // ============================================

  // Rate limiting: track plays per hour and daily tickets
  stable var playLogEntries : [(Principal, Int)] = []; // (player, timestamp)
  stable var dailyTicketEntries : [(Principal, Nat, Int)] = []; // (player, ticketsToday, dayTimestamp)
  stable var accountPlayCountEntries : [(Principal, Nat)] = []; // (player, totalPlays)

  // Do not hydrate from stable state during actor initialization.
  // Legacy classical->enhanced upgrades can still be materializing stable data
  // at this point, and eagerly touching playLogEntries here has trapped live
  // upgrades with a stable-memory out-of-bounds before our migration-safe
  // postupgrade logic can run. Rebuild from stable state inside postupgrade.
  transient var playLog = Buffer.Buffer<(Principal, Int)>(0);
  transient var dailyTickets = HashMap.HashMap<Principal, (Nat, Int)>(32, Principal.equal, Principal.hash); // tickets earned today, day start
  transient var accountPlayCount = HashMap.HashMap<Principal, Nat>(32, Principal.equal, Principal.hash);

  transient let MAX_PLAYS_PER_HOUR : Nat = 20;
  transient let DAILY_TICKET_CAP : Nat = 2000;
  transient let COOLDOWN_NS : Int = 30_000_000_000; // 30 seconds in nanoseconds
  transient let TRIAL_PLAYS : Nat = 0; // legacy stat only; per-game payout config now controls calibration
  transient let MAX_TICKETS_PER_ROUND : Nat = 7;
  transient let JACKPOT_MAX_TICKETS_PER_WIN : Nat = 25;
  transient let JACKPOT_POOL_BASIS_POINTS : Nat = 1000; // 10% of remaining backed pool
  transient let JACKPOT_POOL_PERCENT : Nat = JACKPOT_POOL_BASIS_POINTS / 100; // v1 compatibility default = 10%

  func getDayStart() : Int {
    let now = Time.now();
    // Rough day boundary: round down to nearest 86400 seconds
    now - (now % 86_400_000_000_000);
  };

  func getPlaysInLastHour(player : Principal) : Nat { recentPlaysOf(player, Time.now()).size() };
  func legacyPlaysInLastHour(player : Principal) : Nat {
    let cutoff = Time.now() - 3_600_000_000_000; // 1 hour ago
    var count : Nat = 0;
    if (runtimeStateHydrated) {
      let size = playLog.size();
      var i = size;
      while (i > 0) {
        i -= 1;
        let (p, t) = playLog.get(i);
        if (t < cutoff) { i := 0 }
        else if (Principal.equal(p, player)) { count += 1 };
      };
    } else {
      let size = playLogEntries.size();
      var i = size;
      while (i > 0) {
        i -= 1;
        let (p, t) = playLogEntries[i];
        if (t < cutoff) { i := 0 }
        else if (Principal.equal(p, player)) { count += 1 };
      };
    };
    count;
  };

  func getLastPlayTime(player : Principal) : Int {
    if (runtimeStateHydrated) {
      let size = playLog.size();
      var i = size;
      while (i > 0) {
        i -= 1;
        let (p, t) = playLog.get(i);
        if (Principal.equal(p, player)) return t;
      };
    } else {
      let size = playLogEntries.size();
      var i = size;
      while (i > 0) {
        i -= 1;
        let (p, t) = playLogEntries[i];
        if (Principal.equal(p, player)) return t;
      };
    };
    0;
  };

  func getTotalPlays(player : Principal) : Nat {
    if (runtimeStateHydrated) {
      switch (accountPlayCount.get(player)) { case null 0; case (?v) v };
    } else {
      switch (findPrincipalNat(accountPlayCountEntries, player)) { case null 0; case (?v) v };
    };
  };

  func getDailyTicketsEarned(player : Principal) : Nat {
    let dayStart = getDayStart();
    if (runtimeStateHydrated) {
      switch (dailyTickets.get(player)) {
        case null 0;
        case (?(earned, day)) {
          if (day == dayStart) earned else 0;
        };
      };
    } else {
      for ((entryPlayer, earned, day) in dailyTicketEntries.vals()) {
        if (Principal.equal(entryPlayer, player)) {
          return if (day == dayStart) earned else 0;
        };
      };
      0;
    };
  };

  func addDailyTickets(player : Principal, amount : Nat) {
    let dayStart = getDayStart();
    let current = getDailyTicketsEarned(player);
    dailyTickets.put(player, (current + amount, dayStart));
  };

  func payoutLevels() : [Nat] { [0, 1, 2, 3, 4, 5, 6] };

  func validatePayoutThresholds(thresholds : [Nat]) : Result.Result<(), Text> {
    if (thresholds.size() != 8) {
      return #err("Exactly 8 score thresholds are required");
    };
    var i : Nat = 1;
    while (i < thresholds.size()) {
      if (thresholds[i] < thresholds[i - 1]) {
        return #err("Score thresholds must be ascending/nondecreasing");
      };
      i += 1;
    };
    #ok(());
  };

  func calculateConfiguredTicketPayout(score : Nat, config : GamePayoutConfig) : Nat {
    // 8-level ladder pays 0-7 tickets; older 7-level ladders still work (0-6) until re-saved.
    if (not config.enabled or (config.thresholds.size() != 7 and config.thresholds.size() != 8)) {
      return 0;
    };
    let thresholds = config.thresholds;
    var level : Nat = 0;
    var i : Nat = 0;
    while (i < thresholds.size()) {
      if (score >= thresholds[i]) {
        level := i;
      };
      i += 1;
    };
    if (level > 7) { 7 } else { level };
  };

  func minNat(a : Nat, b : Nat) : Nat {
    if (a < b) { a } else { b };
  };

  func emptyTicketJackpotCalculation() : TicketJackpotCalculation {
    {
      tickets = 0;
      uncappedTickets = 0;
      tierLabels = [];
      tierPayouts = [];
      capped = false;
    };
  };

  // === JACKPOT TIER MODES (session #3) ===
  // Per game: (lowFixed, highFixed). Percent tiers are stored in basis points (1 = 0.01%);
  // fixed tiers store a whole ticket amount. Kept in its own stable list so the config record type is unchanged.
  stable var jackpotTierModeEntries : [(Text, (Bool, Bool))] = [];

  func jackpotTierModes(gameId : Text) : (Bool, Bool) {
    for (e in jackpotTierModeEntries.vals()) { if (e.0 == gameId) return e.1 };
    (false, false)
  };

  func setJackpotTierModes(gameId : Text, lowFixed : Bool, highFixed : Bool) {
    let others = Array.filter<(Text, (Bool, Bool))>(jackpotTierModeEntries, func(e) { e.0 != gameId });
    jackpotTierModeEntries := Array.append<(Text, (Bool, Bool))>(others, [(gameId, (lowFixed, highFixed))]);
  };

  func jackpotTierUncapped(amount : Nat, isFixed : Bool, remainingBacked : Nat) : Nat {
    if (isFixed) { amount } else { remainingBacked * amount / 10_000 }
  };

  func ticketJackpotTierAmount(tierLabel : Text, amount : Nat, isFixed : Bool, remainingBacked : Nat) : TicketJackpotTierPayout {
    {
      tierLabel = tierLabel;
      percent = if (isFixed) { 0 } else { amount };
      uncappedTickets = jackpotTierUncapped(amount, isFixed, remainingBacked);
    };
  };

  func ticketJackpotTierPayout(tierLabel : Text, percent : Nat, remainingBackedAfterBase : Nat) : TicketJackpotTierPayout {
    {
      tierLabel = tierLabel;
      percent = percent;
      uncappedTickets = remainingBackedAfterBase * percent / 10_000;
    };
  };

  func capTicketJackpotPayout(uncappedTickets : Nat, remainingBackedAfterBase : Nat, remainingDailyAfterBase : Nat) : Nat {
    minNat(
      uncappedTickets,
      minNat(minNat(remainingBackedAfterBase, remainingDailyAfterBase), JACKPOT_MAX_TICKETS_PER_WIN),
    );
  };

  func calculateTicketJackpotPayout(gameId : Text, config : GameTicketJackpotConfig, score : Nat, newRecord : Bool, remainingBackedAfterBase : Nat, remainingDailyAfterBase : Nat) : TicketJackpotCalculation {
    if (not config.enabled or remainingBackedAfterBase == 0 or remainingDailyAfterBase == 0) {
      return emptyTicketJackpotCalculation();
    };

    let labels = Buffer.Buffer<Text>(3);
    let payouts = Buffer.Buffer<TicketJackpotTierPayout>(3);
    var uncappedTotal : Nat = 0;

    if (config.highPayoutPercent > 0 and score >= config.highScoreThreshold) {
      let tier = ticketJackpotTierAmount("high", config.highPayoutPercent, jackpotTierModes(gameId).1, remainingBackedAfterBase);
      labels.add("high");
      payouts.add(tier);
      uncappedTotal += tier.uncappedTickets;
    } else if (score >= config.lowScoreThreshold and config.lowPayoutPercent > 0) {
      let tier = ticketJackpotTierAmount("low", config.lowPayoutPercent, jackpotTierModes(gameId).0, remainingBackedAfterBase);
      labels.add("low");
      payouts.add(tier);
      uncappedTotal += tier.uncappedTickets;
    };

    if (newRecord and config.newHighScorePayoutPercent > 0) {
      let tier = ticketJackpotTierPayout("new_high_score", config.newHighScorePayoutPercent, remainingBackedAfterBase);
      labels.add("new_high_score");
      payouts.add(tier);
      uncappedTotal += tier.uncappedTickets;
    };

    let cappedTickets = capTicketJackpotPayout(uncappedTotal, remainingBackedAfterBase, remainingDailyAfterBase);
    {
      tickets = cappedTickets;
      uncappedTickets = uncappedTotal;
      tierLabels = Buffer.toArray(labels);
      tierPayouts = Buffer.toArray(payouts);
      capped = cappedTickets < uncappedTotal;
    };
  };

  func gamePayoutConfigView(gameId : Text, config : GamePayoutConfig) : GamePayoutConfigView {
    {
      gameId = gameId;
      enabled = config.enabled;
      thresholds = config.thresholds;
      payouts = Array.tabulate<Nat>(config.thresholds.size(), func(i : Nat) : Nat { i }); // level N pays N tickets
      updatedAt = config.updatedAt;
    };
  };

  /// Admin: set or update one game's 8-level ticket payout ladder.
  /// Level 1 pays 0 tickets, level 8 pays 7 tickets; thresholds are minimum scores.
  public shared(msg) func setGamePayoutConfig(gameId : Text, enabled : Bool, thresholds : [Nat]) : async Result.Result<GamePayoutConfigView, Text> {
    assert (not isBannedNow(msg.caller)); // banned: only withdrawals, claims and listing allowed
    if (not isAdmin(msg.caller)) return #err("Not authorized");
    hydrateRuntimeStateIfNeeded();
    if (isBlankText(gameId)) return #err("Game ID is required");
    switch (gameSubmissions.get(gameId)) {
      case null { return #err("Game not found: " # gameId) };
      case (?game) {
        if (not isTicketGameSubmission(game)) {
          return #err("Game is not ticket-backed: " # gameId);
        };
      };
    };
    if (thresholds.size() != 8) {
      return #err("Exactly 8 score thresholds are required");
    };
    switch (validatePayoutThresholds(thresholds)) {
      case (#err(message)) { return #err(message) };
      case (#ok(())) {};
    };
    let config : GamePayoutConfig = {
      enabled = enabled;
      thresholds = thresholds;
      updatedAt = Time.now();
    };
    gamePayoutConfigs.put(gameId, config);
    #ok(gamePayoutConfigView(gameId, config));
  };

  public query func getGamePayoutConfig(gameId : Text) : async ?GamePayoutConfigView {
    let config = if (runtimeStateHydrated) {
      gamePayoutConfigs.get(gameId);
    } else {
      findTextValue<GamePayoutConfig>(gamePayoutConfigEntries, gameId);
    };
    switch (config) {
      case null null;
      case (?value) ?gamePayoutConfigView(gameId, value);
    };
  };

  public query func getAllGamePayoutConfigs() : async [GamePayoutConfigView] {
    let entries = if (runtimeStateHydrated) {
      Iter.toArray(gamePayoutConfigs.entries());
    } else {
      gamePayoutConfigEntries;
    };
    Array.map<(Text, GamePayoutConfig), GamePayoutConfigView>(entries, func((gameId, config)) {
      gamePayoutConfigView(gameId, config);
    });
  };

  func gameTicketJackpotConfigView(gameId : Text, config : GameTicketJackpotConfig) : GameTicketJackpotConfigView {
    {
      gameId = gameId;
      enabled = config.enabled;
      lowScoreThreshold = config.lowScoreThreshold;
      lowPayoutPercent = config.lowPayoutPercent;
      highScoreThreshold = config.highScoreThreshold;
      highPayoutPercent = config.highPayoutPercent;
      newHighScorePayoutPercent = config.newHighScorePayoutPercent;
      updatedAt = config.updatedAt;
    };
  };

  // v1 -> v2 defaults preserve Phase 1 behavior: the old scoreThreshold becomes
  // the low tier threshold, low/new-high-score payout percents mirror the
  // existing 10% backed-pool jackpot basis, and the high tier remains disabled.
  func normalizeGameTicketJackpotConfig(legacy : GameTicketJackpotConfigV1) : GameTicketJackpotConfig {
    {
      enabled = legacy.enabled;
      lowScoreThreshold = legacy.scoreThreshold;
      lowPayoutPercent = JACKPOT_POOL_PERCENT * 100;
      highScoreThreshold = 0;
      highPayoutPercent = 0;
      newHighScorePayoutPercent = JACKPOT_POOL_PERCENT * 100;
      updatedAt = legacy.updatedAt;
    };
  };

  func stableGameTicketJackpotConfig(gameId : Text) : ?GameTicketJackpotConfig {
    switch (findTextValue<GameTicketJackpotConfig>(gameTicketJackpotConfigV2Entries, gameId)) {
      case (?config) { ?config };
      case null {
        switch (findTextValue<GameTicketJackpotConfigV1>(gameTicketJackpotConfigEntries, gameId)) {
          case null null;
          case (?legacy) ?normalizeGameTicketJackpotConfig(legacy);
        };
      };
    };
  };

  func stableGameTicketJackpotConfigViews() : [GameTicketJackpotConfigView] {
    let views = Buffer.Buffer<GameTicketJackpotConfigView>(gameTicketJackpotConfigV2Entries.size() + gameTicketJackpotConfigEntries.size());
    for ((gameId, config) in gameTicketJackpotConfigV2Entries.vals()) {
      views.add(gameTicketJackpotConfigView(gameId, config));
    };
    for ((gameId, legacyConfig) in gameTicketJackpotConfigEntries.vals()) {
      switch (findTextValue<GameTicketJackpotConfig>(gameTicketJackpotConfigV2Entries, gameId)) {
        case null { views.add(gameTicketJackpotConfigView(gameId, normalizeGameTicketJackpotConfig(legacyConfig))) };
        case (?_) {};
      };
    };
    Buffer.toArray(views);
  };

  /// Admin: configure Phase 2 ticket jackpot tiers.
  /// The high score jackpot replaces the low score jackpot, and the new high
  /// score bonus can stack with either score tier when a validated record is set.
  public shared(msg) func setGameTicketJackpotConfig(gameId : Text, enabled : Bool, lowScoreThreshold : Nat, lowPayoutPercent : Nat, highScoreThreshold : Nat, highPayoutPercent : Nat, newHighScorePayoutPercent : Nat) : async Result.Result<GameTicketJackpotConfigView, Text> {
    assert (not isBannedNow(msg.caller)); // banned: only withdrawals, claims and listing allowed
    if (not isAdmin(msg.caller)) return #err("Not authorized");
    hydrateRuntimeStateIfNeeded();
    if (Text.size(gameId) == 0) return #err("Game id is required");
    switch (gameSubmissions.get(gameId)) {
      case null { return #err("Unknown game: " # gameId) };
      case (?game) {
        if (game.status != "live" and game.status != "showroom-zip-pending" and game.status != "suspended") {
          return #err("Game must be pending, live or suspended before ticket jackpot configuration: " # gameId);
        };
        if (not isTicketGameSubmission(game)) {
          return #err("Game is not ticket-backed: " # gameId);
        };
      };
    };
    if (enabled and lowScoreThreshold == 0) {
      return #err("Ticket jackpot low score threshold must be greater than 0 when enabled");
    };
    if (enabled and lowPayoutPercent == 0) {
      return #err("Ticket jackpot low payout percent must be greater than 0 when enabled");
    };
    if (highPayoutPercent > 0 and highScoreThreshold <= lowScoreThreshold) {
      return #err("Ticket jackpot high score threshold must be greater than low score threshold when high payout is enabled");
    };
    if (lowPayoutPercent > 100 or highPayoutPercent > 100 or newHighScorePayoutPercent > 100) {
      return #err("Ticket jackpot payout percents must be in the 0..100 range");
    };
    let config : GameTicketJackpotConfig = {
      enabled = enabled;
      lowScoreThreshold = lowScoreThreshold;
      lowPayoutPercent = lowPayoutPercent;
      highScoreThreshold = highScoreThreshold;
      highPayoutPercent = highPayoutPercent;
      newHighScorePayoutPercent = newHighScorePayoutPercent;
      updatedAt = Time.now();
    };
    gameTicketJackpotConfigs.put(gameId, config);
    #ok(gameTicketJackpotConfigView(gameId, config));
  };

  // Jackpot tiers V2: low/high tiers are either % of pool in basis points (1 = 0.01%) or fixed tickets (1..per-win cap).
  public shared(msg) func setGameTicketJackpotConfigV2(gameId : Text, enabled : Bool, lowScoreThreshold : Nat, lowAmount : Nat, lowFixed : Bool, highScoreThreshold : Nat, highAmount : Nat, highFixed : Bool, newHighScoreBps : Nat) : async Result.Result<GameTicketJackpotConfigView, Text> {
    assert (not isBannedNow(msg.caller)); // banned: only withdrawals, claims and listing allowed
    if (not isAdmin(msg.caller)) return #err("Not authorized");
    hydrateRuntimeStateIfNeeded();
    if (Text.size(gameId) == 0) return #err("Game id is required");
    switch (gameSubmissions.get(gameId)) {
      case null { return #err("Unknown game: " # gameId) };
      case (?game) {
        if (game.status != "live" and game.status != "showroom-zip-pending" and game.status != "suspended") {
          return #err("Game must be pending, live or suspended before ticket jackpot configuration: " # gameId);
        };
        if (not isTicketGameSubmission(game)) {
          return #err("Game is not ticket-backed: " # gameId);
        };
      };
    };
    if (enabled and lowScoreThreshold == 0) return #err("Low score threshold must be greater than 0 when enabled");
    if (enabled and lowAmount == 0) return #err("Low tier payout must be greater than 0 when enabled");
    if (highAmount > 0 and highScoreThreshold <= lowScoreThreshold) return #err("High score threshold must be greater than low score threshold when the high tier pays");
    if (lowFixed and lowAmount > JACKPOT_MAX_TICKETS_PER_WIN) return #err("Fixed low tier payout cannot exceed the per-win cap");
    if (highFixed and highAmount > JACKPOT_MAX_TICKETS_PER_WIN) return #err("Fixed high tier payout cannot exceed the per-win cap");
    if ((not lowFixed and lowAmount > 10_000) or (not highFixed and highAmount > 10_000) or newHighScoreBps > 10_000) return #err("Percent payouts must be between 0% and 100%");
    let config : GameTicketJackpotConfig = {
      enabled = enabled;
      lowScoreThreshold = lowScoreThreshold;
      lowPayoutPercent = lowAmount;
      highScoreThreshold = highScoreThreshold;
      highPayoutPercent = highAmount;
      newHighScorePayoutPercent = newHighScoreBps;
      updatedAt = Time.now();
    };
    gameTicketJackpotConfigs.put(gameId, config);
    setJackpotTierModes(gameId, lowFixed, highFixed);
    #ok(gameTicketJackpotConfigView(gameId, config));
  };

  public query func getGameTicketJackpotModes(gameId : Text) : async (Bool, Bool) {
    jackpotTierModes(gameId)
  };

  public query func getGameTicketJackpotConfig(gameId : Text) : async ?GameTicketJackpotConfigView {
    let config = if (runtimeStateHydrated) {
      gameTicketJackpotConfigs.get(gameId);
    } else {
      stableGameTicketJackpotConfig(gameId);
    };
    switch (config) {
      case null null;
      case (?value) ?gameTicketJackpotConfigView(gameId, value);
    };
  };

  public query func getAllGameTicketJackpotConfigs() : async [GameTicketJackpotConfigView] {
    if (runtimeStateHydrated) {
      let entries = Iter.toArray(gameTicketJackpotConfigs.entries());
      Array.map<(Text, GameTicketJackpotConfig), GameTicketJackpotConfigView>(entries, func((gameId, config)) {
        gameTicketJackpotConfigView(gameId, config);
      });
    } else {
      stableGameTicketJackpotConfigViews();
    };
  };

  // Game score submission with anti-bot validation
  type GameResult = {
    gameId : Text;
    score : Nat;
    ticketsEarned : Nat;
    inputHash : Text; // hash of input replay for future verification
    durationMs : Nat; // game duration in milliseconds
  };

  stable var gameResultLog : [GameResult] = [];

  /// Submit a game score and earn tickets (with anti-bot checks)
  // === Anti-cheat: per-game plausibility limits (0 = off), flagged-score review, large-jackpot hold ===
  type FlaggedScore = { id : Nat; player : Principal; gameId : Text; score : Nat; elapsedMs : Nat; reason : Text; heldJackpot : Nat; status : Text; at : Int };
  stable var gameAntiCheatEntries : [(Text, (Nat, Nat, Nat))] = []; // gameId -> (maxScorePerSecond, maxScore, holdJackpotsAbove)
  stable var flaggedScoreEntries : [FlaggedScore] = [];
  stable var flaggedScoreCounter : Nat = 0;
  func antiCheatOf(gameId : Text) : (Nat, Nat, Nat) {
    for ((k, v) in gameAntiCheatEntries.vals()) { if (k == gameId) return v };
    (0, 0, 0)
  };
  func recordFlag(player : Principal, gameId : Text, score : Nat, elapsedMs : Nat, reason : Text, heldJackpot : Nat) {
    flaggedScoreCounter += 1;
    let f : FlaggedScore = { id = flaggedScoreCounter; player = player; gameId = gameId; score = score; elapsedMs = elapsedMs; reason = reason; heldJackpot = heldJackpot; status = if (heldJackpot > 0) { "held" } else { "flagged" }; at = Time.now() };
    var list = flaggedScoreEntries;
    if (list.size() >= 1000) { // drop the oldest entry that is not a held jackpot
      let b = Buffer.Buffer<FlaggedScore>(list.size());
      var dropped = false;
      for (x in list.vals()) { if (not dropped and x.status != "held") { dropped := true } else { b.add(x) } };
      list := Buffer.toArray(b);
    };
    flaggedScoreEntries := Array.append<FlaggedScore>(list, [f]);
  };
  public shared(msg) func adminSetGameAntiCheat(gameId : Text, maxScorePerSecond : Nat, maxScore : Nat, holdJackpotsAbove : Nat) : async Result.Result<Text, Text> {
    if (not isAdmin(msg.caller)) return #err("Not authorized");
    let rest = Array.filter<(Text, (Nat, Nat, Nat))>(gameAntiCheatEntries, func(e) { e.0 != gameId });
    gameAntiCheatEntries := if (maxScorePerSecond == 0 and maxScore == 0 and holdJackpotsAbove == 0) { rest } else { Array.append<(Text, (Nat, Nat, Nat))>(rest, [(gameId, (maxScorePerSecond, maxScore, holdJackpotsAbove))]) };
    #ok("Anti-cheat limits saved")
  };
  public shared query(msg) func getGameAntiCheat(gameId : Text) : async (Nat, Nat, Nat) {
    if (not isAdmin(msg.caller)) return (0, 0, 0);
    antiCheatOf(gameId)
  };
  public shared query(msg) func adminGetFlaggedScores() : async [FlaggedScore] {
    if (not isAdmin(msg.caller)) return [];
    let n = flaggedScoreEntries.size();
    Array.tabulate<FlaggedScore>(n, func(i) { flaggedScoreEntries[n - 1 - i] }) // newest first
  };
  public shared(msg) func adminResolveFlaggedScore(id : Nat, approve : Bool) : async Result.Result<Text, Text> {
    if (not isAdmin(msg.caller)) return #err("Not authorized");
    hydrateRuntimeStateIfNeeded();
    var target : ?FlaggedScore = null;
    for (x in flaggedScoreEntries.vals()) { if (x.id == id) { target := ?x } };
    let f = switch (target) { case null { return #err("Flag not found") }; case (?x) { x } };
    if (f.status != "held" and f.status != "flagged") return #err("Already resolved");
    var paid : Nat = 0;
    if (approve and f.status == "held" and f.heldJackpot > 0) {
      let pool = getGameBackedTicketPoolValue(f.gameId);
      paid := if (f.heldJackpot > pool) { pool } else { f.heldJackpot };
      if (paid > 0) {
        tickets.put(f.player, getTicketBalance(f.player) + paid);
        setGameBackedTicketPoolValue(f.gameId, pool - paid);
        clampBackedPoolToRaw(f.gameId);
      };
    };
    let newStatus = if (approve) { "approved" } else { "rejected" };
    flaggedScoreEntries := Array.map<FlaggedScore, FlaggedScore>(flaggedScoreEntries, func(x) { if (x.id == id) { { x with status = newStatus } } else { x } });
    #ok(if (paid > 0) { "Approved: paid " # Nat.toText(paid) # " held jackpot Tickets" } else { "Marked " # newStatus })
  };

  transient let SHA_K : [Nat32] = [
    0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,
    0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,
    0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,
    0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,
    0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,
    0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,
    0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,
    0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2];
  // SHA-256 of a Text (UTF-8), returned as 64 lowercase hex chars. Small inputs only (run proofs).
  func sha256Hex(t : Text) : Text {
    let msg = Blob.toArray(Text.encodeUtf8(t));
    let ml = msg.size();
    let total = ((ml + 9 + 63) / 64) * 64;
    let buf = Array.tabulate<Nat8>(total, func(i) {
      if (i < ml) msg[i]
      else if (i == ml) 0x80
      else if (i + 8 >= total) {
        let bits : Nat = ml * 8;
        let shift : Nat = Int.abs(total - 1 - i) * 8;
        Nat8.fromNat((bits / (2 ** shift)) % 256)
      } else 0
    });
    var h0 : Nat32 = 0x6a09e667; var h1 : Nat32 = 0xbb67ae85; var h2 : Nat32 = 0x3c6ef372; var h3 : Nat32 = 0xa54ff53a;
    var h4 : Nat32 = 0x510e527f; var h5 : Nat32 = 0x9b05688c; var h6 : Nat32 = 0x1f83d9ab; var h7 : Nat32 = 0x5be0cd19;
    let w = Array.init<Nat32>(64, 0);
    var off = 0;
    while (off < total) {
      var i = 0;
      while (i < 16) {
        let b = off + i * 4;
        w[i] := (Nat32.fromNat(Nat8.toNat(buf[b])) << 24) | (Nat32.fromNat(Nat8.toNat(buf[b + 1])) << 16) | (Nat32.fromNat(Nat8.toNat(buf[b + 2])) << 8) | Nat32.fromNat(Nat8.toNat(buf[b + 3]));
        i += 1;
      };
      while (i < 64) {
        let s0 = (w[i - 15] <>> 7) ^ (w[i - 15] <>> 18) ^ (w[i - 15] >> 3);
        let s1 = (w[i - 2] <>> 17) ^ (w[i - 2] <>> 19) ^ (w[i - 2] >> 10);
        w[i] := w[i - 16] +% s0 +% w[i - 7] +% s1;
        i += 1;
      };
      var a = h0; var b = h1; var c = h2; var d = h3; var e = h4; var f = h5; var g = h6; var h = h7;
      i := 0;
      while (i < 64) {
        let S1 = (e <>> 6) ^ (e <>> 11) ^ (e <>> 25);
        let ch = (e & f) ^ ((^ e) & g);
        let t1 = h +% S1 +% ch +% SHA_K[i] +% w[i];
        let S0 = (a <>> 2) ^ (a <>> 13) ^ (a <>> 22);
        let maj = (a & b) ^ (a & c) ^ (b & c);
        let t2 = S0 +% maj;
        h := g; g := f; f := e; e := d +% t1; d := c; c := b; b := a; a := t1 +% t2;
        i += 1;
      };
      h0 := h0 +% a; h1 := h1 +% b; h2 := h2 +% c; h3 := h3 +% d; h4 := h4 +% e; h5 := h5 +% f; h6 := h6 +% g; h7 := h7 +% h;
      off += 64;
    };
    let hexd = ['0','1','2','3','4','5','6','7','8','9','a','b','c','d','e','f'];
    var out = "";
    for (word in [h0, h1, h2, h3, h4, h5, h6, h7].vals()) {
      var k = 0;
      while (k < 8) {
        let nib = Nat32.toNat((word >> Nat32.fromNat(28 - k * 4)) & 0xf);
        out #= Text.fromChar(hexd[nib]);
        k += 1;
      };
    };
    out
  };

  // === Run check (anti-bot): a game with a run key must prove each score with
  // sha256(key ":" runCode ":" score). The run code is the paid session's openedAt, so an
  // old proof can never be replayed in a new run. Games without a key work exactly as before.
  stable var gameRunKeyEntries : [(Text, Text)] = [];
  func runKeyOf(gameId : Text) : ?Text {
    for ((g, k) in gameRunKeyEntries.vals()) { if (g == gameId) return ?k };
    null
  };
  public shared(msg) func adminSetGameRunKey(gameId : Text, key : Text) : async Result.Result<Text, Text> {
    if (not isAdmin(msg.caller)) return #err("Admin only");
    hydrateRuntimeStateIfNeeded();
    if (gameSubmissions.get(gameId) == null) return #err("Game not found: " # gameId);
    let k = Text.trim(key, #char ' ');
    if (k != "" and (Text.size(k) < 16 or Text.size(k) > 128)) return #err("Run key must be 16 to 128 characters");
    if (Text.contains(k, #char ':')) return #err("Run key cannot contain ':'");
    let kept = Array.filter<(Text, Text)>(gameRunKeyEntries, func((g, _)) { g != gameId });
    gameRunKeyEntries := if (k == "") kept else Array.append<(Text, Text)>(kept, [(gameId, k)]);
    #ok(if (k == "") "Run check off" else "Run check on")
  };
  public query(msg) func adminGetGameRunKey(gameId : Text) : async ?Text {
    if (not isAdmin(msg.caller)) return null;
    runKeyOf(gameId)
  };
  public query func gameHasRunCheck(gameId : Text) : async Bool {
    switch (runKeyOf(gameId)) { case (?_) true; case null false }
  };
  // The caller's run code for their open paid session of this game (null when no run is open).
  public query(msg) func getMyRunNonce(gameId : Text) : async ?Text {
    switch (paidGameSessions.get(paidGameSessionKey(msg.caller, gameId))) {
      case (?session) { if (session.open and Time.now() - session.openedAt < SESSION_MAX_NS) ?Int.toText(session.openedAt) else null };
      case null null;
    }
  };

  // Jackpots are for DAO members (any Voting Power). Badges are checked first (indexed, cheap);
  // the NFT-ability scan only runs for a non-badge holder, and only when a jackpot was actually hit.
  func isJackpotEligible(p : Principal) : Bool {
    if (isAdmin(p)) return true;
    for (badge in getBadgesForOwner(p).vals()) {
      if (Text.startsWith(badge.badgeType, #text "vp-badge-") or badge.badgeType == "dev-contributor" or badge.badgeType == "artist-contributor") return true;
    };
    abilityCountOf(p, "vp-plus") > 0
  };

  // Per-player play times for the last hour (at most MAX_PLAYS_PER_HOUR each). The cooldown and the
  // hourly limit read only the caller's own short list instead of scanning every player's plays, and
  // the global play log no longer grows forever (it was also copied whole before every upgrade).
  transient var recentPlayTimes = HashMap.HashMap<Principal, [Int]>(64, Principal.equal, Principal.hash);
  func recentPlaysOf(player : Principal, now : Int) : [Int] {
    switch (recentPlayTimes.get(player)) {
      case null { [] };
      case (?ts) { Array.filter<Int>(ts, func(t) { t >= now - 3_600_000_000_000 }) };
    }
  };
  func notePlay(player : Principal, now : Int) {
    let kept = recentPlaysOf(player, now);
    let all = Array.append<Int>(kept, [now]);
    let keep : Nat = if (all.size() > MAX_PLAYS_PER_HOUR) { all.size() - MAX_PLAYS_PER_HOUR } else 0;
    recentPlayTimes.put(player, Array.tabulate<Int>(all.size() - keep, func(i) { all[i + keep] }));
  };
  func playedSince(player : Principal, cutoff : Int) : Bool {
    switch (recentPlayTimes.get(player)) {
      case null { false };
      case (?ts) { ts.size() > 0 and ts[ts.size() - 1] >= cutoff };
    }
  };
  transient let GAME_RESULT_LOG_MAX : Nat = 500;

  public shared(msg) func submitGameScore(
    gameId : Text,
    score : Nat,
    tokenCost : Nat,
    inputHash : Text,
    durationMs : Nat
  ) : async Result.Result<{ tickets : Nat; baseTickets : Nat; jackpotTickets : Nat; newRecord : Bool; jackpotTierLabels : [Text]; jackpotUncappedTickets : Nat; jackpotCapped : Bool; jackpotPoolRemaining : Nat; tokenBalance : Nat; ticketBalance : Nat }, Text> {
    assert (not isBannedNow(msg.caller)); // banned: only withdrawals, claims and listing allowed
    let caller = msg.caller;
    if (Principal.isAnonymous(caller)) return #err("Must be authenticated");
    hydrateRuntimeStateIfNeeded();
    if (isBlankText(gameId)) return #err("Game ID is required");

    let game = switch (gameSubmissions.get(gameId)) {
      case null { return #err("Game not found: " # gameId) };
      case (?value) { value };
    };

    if (game.status != "live") return #err("Game is not live: " # gameId);
    if (not isTicketGameSubmission(game)) return #err("Game is not ticket-backed: " # gameId);

    let session = switch (getOpenPaidGameSession(caller, gameId)) {
      case null { return #err("No active paid session") };
      case (?value) { value };
    };
    if (tokenCost != session.tokenCost) {
      return #err("Token cost does not match active session");
    };
    switch (runKeyOf(gameId)) {
      case (?runKey) {
        let expected = sha256Hex(runKey # ":" # Int.toText(session.openedAt) # ":" # Nat.toText(score));
        if (Text.trim(inputHash, #char ' ') != expected) return #err("Run check failed: this score did not come from the game");
      };
      case null {};
    };

    let now = Time.now();

    // CHECK 1: Cooldown (30 seconds between plays)
    if (playedSince(caller, now - COOLDOWN_NS + 1)) {
      return #err("Cooldown: wait 30 seconds between plays");
    };

    // CHECK 2: Rate limit (20 plays per hour)
    if (getPlaysInLastHour(caller) >= MAX_PLAYS_PER_HOUR) {
      return #err("Rate limit: max " # Nat.toText(MAX_PLAYS_PER_HOUR) # " plays per hour");
    };

    // CHECK 3: Paid session finalization. Tokens were already deducted by spendTokensOnGame().
    // Consume before payout mutations so duplicate submits cannot pay twice.
    closePaidGameSession(caller, gameId);

    // Log the play
    notePlay(caller, now);
    let totalPlays = getTotalPlays(caller);
    accountPlayCount.put(caller, totalPlays + 1);

    // CHECK 3b: score plausibility (per-game limits set by admin; 0 = off). The run is timed by the backend from payment.
    let (acMaxRate, acMaxScore, acHoldAbove) = antiCheatOf(gameId);
    let acElapsedMs : Nat = Int.abs(now - session.openedAt) / 1_000_000;
    let acReason : Text = if (acMaxScore > 0 and score > acMaxScore) { "above max score" }
      else if (acMaxRate > 0 and score * 1000 > acMaxRate * (acElapsedMs + 1000)) { "too fast for the run's length" }
      else { "" };
    if (acReason != "") {
      recordFlag(caller, gameId, score, acElapsedMs, acReason, 0);
      return #ok({ tickets = 0; baseTickets = 0; jackpotTickets = 0; newRecord = false; jackpotTierLabels = []; jackpotUncappedTickets = 0; jackpotCapped = false; jackpotPoolRemaining = getGameBackedTicketPoolValue(gameId); tokenBalance = getTokenBalance(caller); ticketBalance = getTicketBalance(caller) });
    };

    // CHECK 4: Calculate tickets from the admin-calibrated per-game payout table.
    // Missing or disabled config is explicit calibration-off mode and pays 0.
    var ticketPayout : Nat = switch (gamePayoutConfigs.get(gameId)) {
      case null 0;
      case (?config) calculateConfiguredTicketPayout(score, config);
    };

    // CHECK 5: Hard cap normal payouts at 7 tickets (top of the 8-level ladder).
    if (ticketPayout > MAX_TICKETS_PER_ROUND) { ticketPayout := MAX_TICKETS_PER_ROUND };

    // CHECK 7: Daily ticket cap
    let dailyEarned = getDailyTicketsEarned(caller);
    if (dailyEarned >= DAILY_TICKET_CAP) {
      ticketPayout := 0; // hit daily cap
    } else if (dailyEarned + ticketPayout > DAILY_TICKET_CAP) {
      ticketPayout := DAILY_TICKET_CAP - dailyEarned; // partial payout to cap
    };

    // CHECK 8: Model A backed-pool enforcement.
    // Fail closed by capping payout to what this game has explicitly backed.
    let availableBackedPool = getGameBackedTicketPoolValue(gameId);
    if (ticketPayout > availableBackedPool) {
      ticketPayout := availableBackedPool;
    };

    let baseTickets : Nat = ticketPayout;
    updatePlayerBest(caller, gameId, score);
    let newRecord = if (isRetiredBreaker(gameId, caller)) { false } else { markBrokenGhosts(gameId, caller, score); updateGameTopScores(gameId, caller, score); recordValidatedHighScore(caller, gameId, score) };
    let jackpotConfig = gameTicketJackpotConfigs.get(gameId);
    let remainingBackedAfterBase : Nat = availableBackedPool - baseTickets;
    let remainingDailyAfterBase : Nat = if (dailyEarned + baseTickets >= DAILY_TICKET_CAP) {
      0;
    } else {
      DAILY_TICKET_CAP - (dailyEarned + baseTickets);
    };
    let jackpotCalculation = switch (jackpotConfig) {
      case null emptyTicketJackpotCalculation();
      case (?config) {
        if (config.enabled) {
          calculateTicketJackpotPayout(gameId, config, score, newRecord, remainingBackedAfterBase, remainingDailyAfterBase);
        } else {
          emptyTicketJackpotCalculation();
        };
      };
    };
    var jackpotTickets : Nat = jackpotCalculation.tickets;
    var jackpotLabelsOut : [Text] = jackpotCalculation.tierLabels;
    if (jackpotTickets > 0 and not isJackpotEligible(caller)) { jackpotTickets := 0; jackpotLabelsOut := ["dao_members_only"] };
    if (acHoldAbove > 0 and jackpotTickets > acHoldAbove) {
      recordFlag(caller, gameId, score, acElapsedMs, "large jackpot held for review", jackpotTickets);
      jackpotTickets := 0;
    };
    let totalTicketPayout : Nat = baseTickets + jackpotTickets;

    // Award base + jackpot tickets atomically and decrement only the backed pool.
    if (totalTicketPayout > 0) {
      let tickBal = getTicketBalance(caller);
      tickets.put(caller, tickBal + totalTicketPayout);
      addDailyTickets(caller, totalTicketPayout);
      setGameBackedTicketPoolValue(gameId, availableBackedPool - totalTicketPayout);
      clampBackedPoolToRaw(gameId);
      addGxp(caller, totalTicketPayout);
    };

    if (jackpotTickets > 0) {
      ticketJackpotWins.add({
        player = caller;
        gameId = gameId;
        score = score;
        jackpotTickets = jackpotTickets;
        baseTickets = baseTickets;
        timestamp = now;
      });
      ticketJackpotWinDetails.add({
        player = caller;
        gameId = gameId;
        score = score;
        jackpotTickets = jackpotTickets;
        baseTickets = baseTickets;
        tierLabels = jackpotCalculation.tierLabels;
        uncappedTickets = jackpotCalculation.uncappedTickets;
        capped = jackpotCalculation.capped;
        timestamp = now;
      });
    };

    // Log game result
    let resultEntry : GameResult = { gameId = gameId; score = score; ticketsEarned = totalTicketPayout; inputHash = inputHash; durationMs = durationMs };
    let resultOld = gameResultLog;
    let resultSkip : Nat = if (resultOld.size() >= GAME_RESULT_LOG_MAX) { resultOld.size() + 1 - GAME_RESULT_LOG_MAX } else 0;
    gameResultLog := Array.tabulate<GameResult>(resultOld.size() - resultSkip + 1, func(i) { if (i + resultSkip < resultOld.size()) resultOld[i + resultSkip] else resultEntry });

    #ok({
      tickets = totalTicketPayout;
      baseTickets = baseTickets;
      jackpotTickets = jackpotTickets;
      newRecord = newRecord;
      jackpotTierLabels = jackpotLabelsOut;
      jackpotUncappedTickets = jackpotCalculation.uncappedTickets;
      jackpotCapped = jackpotCalculation.capped;
      jackpotPoolRemaining = getGameBackedTicketPoolValue(gameId);
      tokenBalance = getTokenBalance(caller);
      ticketBalance = getTicketBalance(caller);
    });
  };

  /// Force-close an open paid game session without ticket payout.
  // === On-chain checkpoints (saved spots), keyed player::gameId; survives upgrades (stable Trie). ===
  stable var gameCheckpoints : Trie.Trie<Text, Text> = Trie.empty();
  transient let CHECKPOINT_MAX_CHARS : Nat = 32_000;
  func checkpointKey(k : Text) : Trie.Key<Text> { { hash = Text.hash(k); key = k } };
  public shared(msg) func saveCheckpoint(gameId : Text, data : Text) : async Result.Result<Text, Text> {
    assert (not isBannedNow(msg.caller)); // banned: only withdrawals, claims and listing allowed
    if (Principal.isAnonymous(msg.caller)) return #err("Must be authenticated");
    if (isBlankText(gameId)) return #err("Game ID is required");
    if (Text.size(data) > CHECKPOINT_MAX_CHARS) return #err("Checkpoint too large (max 32,000 characters)");
    hydrateRuntimeStateIfNeeded();
    switch (gameSubmissions.get(gameId)) { case null { return #err("Game not found") }; case (?_) {} };
    let k = Principal.toText(msg.caller) # "::" # gameId;
    gameCheckpoints := Trie.put(gameCheckpoints, checkpointKey(k), Text.equal, data).0;
    #ok("Checkpoint saved")
  };
  public query func getCheckpoint(player : Principal, gameId : Text) : async ?Text {
    Trie.get(gameCheckpoints, checkpointKey(Principal.toText(player) # "::" # gameId), Text.equal)
  };
  public shared(msg) func clearCheckpoint(gameId : Text) : async Result.Result<Text, Text> {
    assert (not isBannedNow(msg.caller)); // banned: only withdrawals, claims and listing allowed
    if (Principal.isAnonymous(msg.caller)) return #err("Must be authenticated");
    let k = Principal.toText(msg.caller) # "::" # gameId;
    gameCheckpoints := Trie.remove(gameCheckpoints, checkpointKey(k), Text.equal).0;
    #ok("Checkpoint cleared")
  };
  // When the caller's open (non-expired) session for this game started, so the frontend can enforce the 2-hour limit.
  public shared query(msg) func getMyOpenSession(gameId : Text) : async ?Int {
    hydrateRuntimeStateIfNeeded();
    switch (getOpenPaidGameSession(msg.caller, gameId)) { case (?ses) ?ses.openedAt; case null null }
  };

  public shared(msg) func endGameSession(gameId : Text) : async Result.Result<Text, Text> {
    let caller = msg.caller;
    if (Principal.isAnonymous(caller)) return #err("Must be authenticated");
    hydrateRuntimeStateIfNeeded();
    if (isBlankText(gameId)) return #err("Game ID is required");
    switch (getOpenPaidGameSession(caller, gameId)) {
      case null { return #err("No active paid session") };
      case (?_) {
        closePaidGameSession(caller, gameId);
        #ok("Session closed");
      };
    };
  };

  /// Get player game stats
  public query func getPlayerGameStats(player : Principal) : async {
    totalPlays : Nat;
    dailyTicketsEarned : Nat;
    dailyTicketCap : Nat;
    playsThisHour : Nat;
    maxPlaysPerHour : Nat;
    trialPlaysRemaining : Nat;
  } {
    let total = getTotalPlays(player);
    {
      totalPlays = total;
      dailyTicketsEarned = getDailyTicketsEarned(player);
      dailyTicketCap = DAILY_TICKET_CAP;
      playsThisHour = getPlaysInLastHour(player);
      maxPlaysPerHour = MAX_PLAYS_PER_HOUR;
      trialPlaysRemaining = if (total >= TRIAL_PLAYS) 0 else TRIAL_PLAYS - total;
    };
  };

  // === LEADERBOARD ===
  type LeaderboardEntry = {
    player : Principal;
    score : Nat;
    gameId : Text;
    timestamp : Int;
  };

  stable var leaderboardEntries : [(Text, LeaderboardEntry)] = []; // gameId -> top score

  // New (v4) - Model A ticket accounting separation
  // IMPORTANT: keep these appended after the legacy stable fields above.
  // Changing stable field order can break upgrades against older live canister layouts.
  stable var gameRawTicketPoolEntries : [(Text, Nat)] = [];
  stable var gameBackedTicketPoolEntries : [(Text, Nat)] = [];
  stable var paidGameSessionEntries : [(Text, PaidGameSession)] = [];
  stable var gamePurchaseEntries : [(Text, Bool)] = [];
  // Cumulative tokens a player has spent on one specific game, per-(player,game) - powers the
  // auto-unlock path: once this total reaches the game's purchasePrice, spendTokensOnGame flips
  // the same gamePurchases flag purchaseGame uses, no separate purchase transaction needed since
  // the value already moved through each individual play's normal revenue split as it happened.
  stable var gameTokenSpendEntries : [(Text, Nat)] = [];
  stable var gamePayoutConfigEntries : [(Text, GamePayoutConfig)] = [];

  type TicketJackpotWin = {
    player : Principal;
    gameId : Text;
    score : Nat;
    jackpotTickets : Nat;
    baseTickets : Nat;
    timestamp : Int;
  };

  type TicketJackpotWinDetail = {
    player : Principal;
    gameId : Text;
    score : Nat;
    jackpotTickets : Nat;
    baseTickets : Nat;
    tierLabels : [Text];
    uncappedTickets : Nat;
    capped : Bool;
    timestamp : Int;
  };

  stable var ticketJackpotWinEntries : [TicketJackpotWin] = [];
  stable var gameTicketJackpotConfigEntries : [(Text, GameTicketJackpotConfigV1)] = [];
  stable var gameTicketJackpotConfigV2Entries : [(Text, GameTicketJackpotConfig)] = [];
  stable var ticketJackpotWinTierEntries : [TicketJackpotWinDetail] = [];
  stable var tipReceiptEntries : [TipReceipt] = [];

  transient var ticketJackpotWins = Buffer.Buffer<TicketJackpotWin>(0);
  transient var ticketJackpotWinDetails = Buffer.Buffer<TicketJackpotWinDetail>(0);
  transient var leaderboards = HashMap.HashMap<Text, LeaderboardEntry>(8, Text.equal, textHash);

  // === BREAKERS + TOP SCORES (session #3, phase 1) ===
  // Top 10 best scores per game (one entry per player). Retiring the #1 "Breaker" keeps their score as the
  // ghost ceiling, stops their future runs on that game counting, and promotes #2 to be the record to beat,
  // so the new-high-score jackpot bonus becomes reachable again. Badges come in phase 2 (badgeId = "").
  stable var gameTopScoreEntries : [(Text, [(Principal, Nat, Int)])] = [];
  stable var retiredBreakerEntries : [(Text, Principal, Text, Nat, Int)] = [];

  func gameTopScores(gameId : Text) : [(Principal, Nat, Int)] {
    for (e in gameTopScoreEntries.vals()) { if (e.0 == gameId) return e.1 };
    []
  };

  func putGameTopScores(gameId : Text, list : [(Principal, Nat, Int)]) {
    let others = Array.filter<(Text, [(Principal, Nat, Int)])>(gameTopScoreEntries, func(e) { e.0 != gameId });
    gameTopScoreEntries := if (list.size() == 0) { others } else { Array.append<(Text, [(Principal, Nat, Int)])>(others, [(gameId, list)]) };
  };

  // Entry layout: (gameId, retiredPlayer, brokenBy, retiredScore, retiredAt). brokenBy is "" while the
  // ghost score stands; once another jackpot-eligible player beats it, brokenBy holds their principal
  // text and the retired player is a normal player on that game again.
  func isRetiredBreaker(gameId : Text, p : Principal) : Bool {
    for (b in retiredBreakerEntries.vals()) { if (b.0 == gameId and Principal.equal(b.1, p) and b.2 == "") return true };
    false
  };

  // Called on every validated score: if this score beats a standing ghost ceiling set by someone
  // else, and the scorer could win jackpots (DAO member), the ghost is marked broken.
  func markBrokenGhosts(gameId : Text, scorer : Principal, score : Nat) {
    var any = false;
    for (b in retiredBreakerEntries.vals()) {
      if (b.0 == gameId and b.2 == "" and not Principal.equal(b.1, scorer) and score > b.3) { any := true };
    };
    if (not any) return;
    if (not isJackpotEligible(scorer)) return;
    let who = Principal.toText(scorer);
    retiredBreakerEntries := Array.map<(Text, Principal, Text, Nat, Int), (Text, Principal, Text, Nat, Int)>(retiredBreakerEntries, func(b) {
      if (b.0 == gameId and b.2 == "" and not Principal.equal(b.1, scorer) and score > b.3) { (b.0, b.1, who, b.3, b.4) } else { b }
    });
  };

  func updateGameTopScores(gameId : Text, player : Principal, score : Nat) {
    var list = gameTopScores(gameId);
    if (list.size() == 0) {
      switch (leaderboards.get(gameId)) {
        case (?cur) { if (not isRetiredBreaker(gameId, cur.player)) { list := [(cur.player, cur.score, cur.timestamp)] } };
        case null {};
      };
    };
    let buf = Buffer.Buffer<(Principal, Nat, Int)>(list.size() + 1);
    var found = false;
    for (e in list.vals()) {
      if (Principal.equal(e.0, player)) {
        found := true;
        if (score > e.1) { buf.add((player, score, Time.now())) } else { buf.add(e) };
      } else { buf.add(e) };
    };
    if (not found) { buf.add((player, score, Time.now())) };
    let sorted = Array.sort<(Principal, Nat, Int)>(Buffer.toArray(buf), func(a, b) {
      if (a.1 > b.1) { #less } else if (a.1 < b.1) { #greater } else if (a.2 < b.2) { #less } else if (a.2 > b.2) { #greater } else { #equal }
    });
    let top = if (sorted.size() > 10) { Array.tabulate<(Principal, Nat, Int)>(10, func(i) { sorted[i] }) } else { sorted };
    putGameTopScores(gameId, top);
  };

  public shared(msg) func adminRetireBreaker(gameId : Text, player : Principal) : async Result.Result<Text, Text> {
    assert (not isBannedNow(msg.caller)); // banned: only withdrawals, claims and listing allowed
    if (not isAdmin(msg.caller)) return #err("Not authorized");
    hydrateRuntimeStateIfNeeded();
    retireBreakerInternal(gameId, player)
  };

  func retireBreakerInternal(gameId : Text, player : Principal) : Result.Result<Text, Text> {
    let current = switch (leaderboards.get(gameId)) {
      case null { return #err("This game has no record yet") };
      case (?c) c;
    };
    if (not Principal.equal(current.player, player)) return #err("Only the current #1 record holder can be retired");
    if (isRetiredBreaker(gameId, player)) return #err("This player is already retired on this game");
    var list = gameTopScores(gameId);
    if (list.size() == 0) { list := [(current.player, current.score, current.timestamp)] };
    let rest = Array.filter<(Principal, Nat, Int)>(list, func(e) { not Principal.equal(e.0, player) and not isRetiredBreaker(gameId, e.0) });
    if (rest.size() == 0) return #err("No #2 score recorded yet. Retiring now would let any score claim the new-record bonus; wait until another player has a validated score.");
    let next = rest[0];
    retiredBreakerEntries := Array.append<(Text, Principal, Text, Nat, Int)>(retiredBreakerEntries, [(gameId, player, "", current.score, Time.now())]);
    putGameTopScores(gameId, rest);
    leaderboards.put(gameId, { player = next.0; score = next.1; gameId = gameId; timestamp = next.2 });
    #ok("Retired. Ghost ceiling: " # Nat.toText(current.score) # ". New #1 to beat: " # Nat.toText(next.1) # ".");
  };

  /// Who would be retired right now (current #1), for the admin confirm dialog.
  public query func getRetireCandidate(gameId : Text) : async ?{ player : Principal; name : Text; score : Nat; hasRunnerUp : Bool } {
    let lb = if (runtimeStateHydrated) { leaderboards.get(gameId) } else { findTextValue<LeaderboardEntry>(leaderboardEntries, gameId) };
    switch (lb) {
      case null null;
      case (?cur) {
        let list = gameTopScores(gameId);
        let rest = Array.filter<(Principal, Nat, Int)>(list, func(e) { not Principal.equal(e.0, cur.player) and not isRetiredBreaker(gameId, e.0) });
        let nm = switch (getPlayerProfileOpt(cur.player)) { case (?p) p.name; case null "" };
        ?{ player = cur.player; name = nm; score = cur.score; hasRunnerUp = rest.size() > 0 }
      };
    };
  };

  /// Retire whoever holds the record right now (same rules as adminRetireBreaker). Calls the shared
  /// internal routine directly: a self-call would arrive with the canister as msg.caller and fail the admin check.
  public shared(msg) func adminRetireBreakerCurrent(gameId : Text) : async Result.Result<Text, Text> {
    assert (not isBannedNow(msg.caller)); // banned: only withdrawals, claims and listing allowed
    if (not isAdmin(msg.caller)) return #err("Not authorized");
    hydrateRuntimeStateIfNeeded();
    switch (leaderboards.get(gameId)) {
      case null #err("This game has no record yet");
      case (?cur) retireBreakerInternal(gameId, cur.player);
    };
  };

  public query func getAllBreakers() : async [(Text, Principal, Text, Nat, Int)] {
    retiredBreakerEntries
  };

  public query func getBreakers(gameId : Text) : async [(Text, Principal, Text, Nat, Int)] {
    Array.filter<(Text, Principal, Text, Nat, Int)>(retiredBreakerEntries, func(b) { b.0 == gameId })
  };

  public query func getBreakerScore(gameId : Text) : async Nat {
    var m : Nat = 0;
    for (b in retiredBreakerEntries.vals()) { if (b.0 == gameId and b.3 > m) { m := b.3 } };
    m
  };

  public query func getGameTopScores(gameId : Text) : async [(Principal, Nat, Int)] {
    gameTopScores(gameId)
  };

  // === PROFILE DATA (session #3, profile stage 1) ===
  // Personal bests per player per Showroom Ticket game (submitGameScore only runs for Ticket games) and the
  // public Hang-5 NFT wall ("<canisterId>:<tokenId>" refs; ownership is checked at view time in the browser).
  stable var playerBestEntries : [(Principal, [(Text, Nat, Int)])] = [];
  stable var profileWallEntries : [(Principal, [Text])] = [];
  transient var playerBests = HashMap.HashMap<Principal, [(Text, Nat, Int)]>(32, Principal.equal, Principal.hash);
  transient var profileWalls = HashMap.HashMap<Principal, [Text]>(32, Principal.equal, Principal.hash);

  func updatePlayerBest(player : Principal, gameId : Text, score : Nat) {
    let list = switch (playerBests.get(player)) { case null { [] }; case (?l) { l } };
    let buf = Buffer.Buffer<(Text, Nat, Int)>(list.size() + 1);
    var found = false;
    for (e in list.vals()) {
      if (e.0 == gameId) {
        found := true;
        if (score > e.1) { buf.add((gameId, score, Time.now())) } else { buf.add(e) };
      } else { buf.add(e) };
    };
    if (not found) { buf.add((gameId, score, Time.now())) };
    playerBests.put(player, Buffer.toArray(buf));
  };

  func playerBestsOf(player : Principal) : [(Text, Nat, Int)] {
    if (runtimeStateHydrated) {
      switch (playerBests.get(player)) { case null { [] }; case (?l) { l } };
    } else {
      for (e in playerBestEntries.vals()) { if (Principal.equal(e.0, player)) return e.1 };
      [];
    };
  };

  func profileWallOf(player : Principal) : [Text] {
    if (runtimeStateHydrated) {
      switch (profileWalls.get(player)) { case null { [] }; case (?l) { l } };
    } else {
      for (e in profileWallEntries.vals()) { if (Principal.equal(e.0, player)) return e.1 };
      [];
    };
  };

  public shared(msg) func setProfileWall(items : [Text]) : async Result.Result<[Text], Text> {
    assert (not isBannedNow(msg.caller)); // banned: only withdrawals, claims and listing allowed
    let caller = msg.caller;
    if (Principal.isAnonymous(caller)) return #err("Must be authenticated");
    hydrateRuntimeStateIfNeeded();
    if (items.size() > 5) return #err("You can hang at most 5 NFTs");
    let buf = Buffer.Buffer<Text>(5);
    for (it in items.vals()) {
      if (Text.size(it) == 0 or Text.size(it) > 200) return #err("Invalid NFT reference");
      var dup = false;
      for (x in buf.vals()) { if (x == it) { dup := true } };
      if (dup) return #err("The same NFT can only be hung once");
      buf.add(it);
    };
    let arr = Buffer.toArray(buf);
    if (arr.size() == 0) { profileWalls.delete(caller) } else { profileWalls.put(caller, arr) };
    #ok(arr);
  };

  public query func getProfileWall(player : Principal) : async [Text] {
    profileWallOf(player)
  };

  public query func getPlayerBests(player : Principal) : async [(Text, Nat, Int)] {
    playerBestsOf(player)
  };

  public query func getPlayerRankings(player : Principal) : async { records : [(Text, Nat)]; topTen : [(Text, Nat, Nat)]; breakers : [(Text, Nat, Int)] } {
    let recs = Buffer.Buffer<(Text, Nat)>(4);
    let lb = if (runtimeStateHydrated) { Iter.toArray(leaderboards.entries()) } else { leaderboardEntries };
    for ((gid, e) in lb.vals()) { if (Principal.equal(e.player, player)) { recs.add((gid, e.score)) } };
    let tops = Buffer.Buffer<(Text, Nat, Nat)>(4);
    for ((gid, list) in gameTopScoreEntries.vals()) {
      var rank : Nat = 0;
      for (e in list.vals()) {
        rank += 1;
        if (Principal.equal(e.0, player)) { tops.add((gid, rank, e.1)) };
      };
    };
    let brk = Buffer.Buffer<(Text, Nat, Int)>(2);
    for (b in retiredBreakerEntries.vals()) { if (Principal.equal(b.1, player)) { brk.add((b.0, b.3, b.4)) } };
    { records = Buffer.toArray(recs); topTen = Buffer.toArray(tops); breakers = Buffer.toArray(brk) };
  };

  public query func getPlayerJackpotWins(player : Principal, limit : Nat) : async [TicketJackpotWin] {
    let cap = if (limit > 50) { 50 } else { limit };
    let all = if (runtimeStateHydrated) { Buffer.toArray(ticketJackpotWins) } else { ticketJackpotWinEntries };
    let out = Buffer.Buffer<TicketJackpotWin>(8);
    var i = all.size();
    while (i > 0 and out.size() < cap) {
      i -= 1;
      let w = all[i];
      if (Principal.equal(w.player, player) and w.jackpotTickets > 0) { out.add(w) };
    };
    Buffer.toArray(out);
  };

  func recordValidatedHighScore(player : Principal, gameId : Text, score : Nat) : Bool {
    switch (leaderboards.get(gameId)) {
      case null {
        leaderboards.put(gameId, { player = player; score = score; gameId = gameId; timestamp = Time.now() });
        true;
      };
      case (?current) {
        if (score > current.score) {
          leaderboards.put(gameId, { player = player; score = score; gameId = gameId; timestamp = Time.now() });
          true;
        } else {
          false;
        };
      };
    };
  };

  /// Get high score for a game
  public query func getHighScore(gameId : Text) : async ?LeaderboardEntry {
    if (runtimeStateHydrated) {
      leaderboards.get(gameId);
    } else {
      findTextValue<LeaderboardEntry>(leaderboardEntries, gameId);
    };
  };

  /// Get all high scores
  public query func getAllHighScores() : async [(Text, LeaderboardEntry)] {
    if (runtimeStateHydrated) {
      Iter.toArray(leaderboards.entries());
    } else {
      leaderboardEntries;
    };
  };

  /// Submit high score manually. Player-facing high scores must go through
  /// submitGameScore() so records are tied to a validated paid session.
  public shared(msg) func submitHighScore(gameId : Text, score : Nat) : async Result.Result<Bool, Text> {
    assert (not isBannedNow(msg.caller)); // banned: only withdrawals, claims and listing allowed
    let caller = msg.caller;
    if (Principal.isAnonymous(caller)) return #err("Must be authenticated");
    hydrateRuntimeStateIfNeeded();
    if (not isAdmin(caller)) {
      return #err("Player high scores must be submitted through submitGameScore");
    };
    #ok(recordValidatedHighScore(caller, gameId, score));
  };

  /// Award tickets to a player (admin only for manual awards)
  public shared(msg) func awardTickets(player : Principal, amount : Nat) : async Result.Result<Nat, Text> {
    assert (not isBannedNow(msg.caller)); // banned: only withdrawals, claims and listing allowed
    if (not ALLOW_TEST_MINTING) return #err("Test minting is disabled on this network");
    if (not isAdmin(msg.caller)) return #err("Not authorized — use submitGameScore for game rewards");
    hydrateRuntimeStateIfNeeded();
    let current = getTicketBalance(player);
    let newBal = current + amount;
    tickets.put(player, newBal);
    #ok(newBal);
  };

  /// Get token balance
  public query func getTokens(player : Principal) : async Nat {
    getTokenBalance(player);
  };

  // ============================================
  // === NFT LISTINGS ===
  // ============================================

  func createExistingNftListing(
    caller : Principal,
    name : Text,
    description : Text,
    rarity : Text,
    ticketCost : Nat,
    imageUrl : Text,
    sourceCanisterId : Text,
    sourceTokenId : Nat,
    sourceTokenKey : Text,
    collectionName : Text,
    feeTxId : Nat
  ) : Result.Result<Text, Text> {
    if (Principal.isAnonymous(caller)) return #err("Must be authenticated");
    hydrateRuntimeStateIfNeeded();
    if (Text.size(name) == 0) return #err("Name required");
    if (ticketCost < 25) return #err("Minimum ticket cost is 25");
    switch (chargeNftListingFee(caller)) {
      case (#err(err)) { return #err(err) };
      case (#ok(())) {};
    };

    let id = genListingId("nft-ex");
    let normalizedSourceTokenKey = if (Text.size(sourceTokenKey) > 0) sourceTokenKey else Nat.toText(sourceTokenId);
    let listing : NftListing = {
      id = id;
      listingType = "existing";
      name = name;
      description = description;
      rarity = rarity;
      ticketCost = ticketCost;
      imageUrl = imageUrl;
      creator = caller;
      tier = "open";
      status = "live";
      feePaid = NFT_LISTING_FEE_E8S; // 5 Tokens = 0.05 ICP equivalent
      showroomFeePaid = 0;
      txId = feeTxId;
      createdAt = Time.now();
      sourceCanisterId = sourceCanisterId;
      sourceTokenId = sourceTokenId;
      sourceTokenKey = normalizedSourceTokenKey;
      collectionName = collectionName;
    };
    nftListings.put(id, listing);
    logRevenue("nft-list", NFT_LISTING_FEE_E8S, caller, 1);
    #ok(id);
  };

  func createPendingExistingNftListing(
    caller : Principal,
    name : Text,
    description : Text,
    rarity : Text,
    ticketCost : Nat,
    imageUrl : Text,
    sourceCanisterId : Text,
    sourceTokenId : Nat,
    sourceTokenKey : Text,
    collectionName : Text,
    feeTxId : Nat
  ) : Result.Result<Text, Text> {
    if (Principal.isAnonymous(caller)) return #err("Must be authenticated");
    hydrateRuntimeStateIfNeeded();
    if (Text.size(name) == 0) return #err("Name required");
    if (ticketCost < 25) return #err("Minimum ticket cost is 25");
    if (Text.size(sourceCanisterId) == 0) return #err("Source canister required");
    switch (chargeNftListingFee(caller)) {
      case (#err(err)) { return #err(err) };
      case (#ok(())) {};
    };

    let id = genListingId("nft-pending");
    let normalizedSourceTokenKey = if (Text.size(sourceTokenKey) > 0) sourceTokenKey else Nat.toText(sourceTokenId);
    let listing : NftListing = {
      id = id;
      listingType = "existing";
      name = name;
      description = description;
      rarity = rarity;
      ticketCost = ticketCost;
      imageUrl = imageUrl;
      creator = caller;
      tier = "open";
      status = "pending_escrow";
      feePaid = NFT_LISTING_FEE_E8S;
      showroomFeePaid = 0;
      txId = feeTxId;
      createdAt = Time.now();
      sourceCanisterId = sourceCanisterId;
      sourceTokenId = sourceTokenId;
      sourceTokenKey = normalizedSourceTokenKey;
      collectionName = collectionName;
    };
    nftListings.put(id, listing);
    logRevenue("nft-list", NFT_LISTING_FEE_E8S, caller, 1);
    #ok(id);
  };

  /// Submit a new NFT listing (existing NFT from circulation).
  /// Legacy-compatible path: numeric standards retain sourceTokenId and sourceTokenKey falls back to Nat.toText(sourceTokenId).
  public shared(msg) func listExistingNft(
    name : Text,
    description : Text,
    rarity : Text,
    ticketCost : Nat,
    imageUrl : Text,
    sourceCanisterId : Text,
    sourceTokenId : Nat,
    collectionName : Text,
    feeTxId : Nat
  ) : async Result.Result<Text, Text> {
    createExistingNftListing(msg.caller, name, description, rarity, ticketCost, imageUrl, sourceCanisterId, sourceTokenId, Nat.toText(sourceTokenId), collectionName, feeTxId)
  };

  /// Additive EXT-safe listing path. Keeps the old listExistingNft signature stable while preserving full text token ids.
  public shared(msg) func listExistingNftWithTokenKey(
    name : Text,
    description : Text,
    rarity : Text,
    ticketCost : Nat,
    imageUrl : Text,
    sourceCanisterId : Text,
    sourceTokenId : Nat,
    sourceTokenKey : Text,
    collectionName : Text,
    feeTxId : Nat
  ) : async Result.Result<Text, Text> {
    createExistingNftListing(msg.caller, name, description, rarity, ticketCost, imageUrl, sourceCanisterId, sourceTokenId, sourceTokenKey, collectionName, feeTxId)
  };

  /// Additive safer listing path. Creates a recoverable pending listing before any NFT moves into arcade escrow.
  public shared(msg) func createPendingExistingNftListingWithTokenKey(
    name : Text,
    description : Text,
    rarity : Text,
    ticketCost : Nat,
    imageUrl : Text,
    sourceCanisterId : Text,
    sourceTokenId : Nat,
    sourceTokenKey : Text,
    collectionName : Text,
    feeTxId : Nat
  ) : async Result.Result<Text, Text> {
    createPendingExistingNftListing(msg.caller, name, description, rarity, ticketCost, imageUrl, sourceCanisterId, sourceTokenId, sourceTokenKey, collectionName, feeTxId)
  };

  /// Submit a new minted NFT
  public shared(msg) func listMintedNft(
    name : Text,
    description : Text,
    rarity : Text,
    ticketCost : Nat,
    imageUrl : Text,
    feeTxId : Nat
  ) : async Result.Result<Text, Text> {
    let caller = msg.caller;
    if (Principal.isAnonymous(caller)) return #err("Must be authenticated");
    hydrateRuntimeStateIfNeeded();
    if (Text.size(name) == 0) return #err("Name required");
    if (ticketCost < 25) return #err("Minimum ticket cost is 25");

    let id = genListingId("nft-mint");
    let listing : NftListing = {
      id = id;
      listingType = "mint";
      name = name;
      description = description;
      rarity = rarity;
      ticketCost = ticketCost;
      imageUrl = imageUrl;
      creator = caller;
      tier = "open";
      status = "live";
      feePaid = 25_000_000; // 0.25 ICP
      showroomFeePaid = 0;
      txId = feeTxId;
      createdAt = Time.now();
      sourceCanisterId = "";
      sourceTokenId = 0;
      sourceTokenKey = "";
      collectionName = "";
    };
    nftListings.put(id, listing);
    logRevenue("nft-mint", 25_000_000, caller, 2);
    #ok(id);
  };

  /// Admin: promote to Jay's Picks
  public shared(msg) func promoteNftToJaysPicks(listingId : Text) : async Result.Result<Text, Text> {
    assert (not isBannedNow(msg.caller)); // banned: only withdrawals, claims and listing allowed
    if (not isAdmin(msg.caller)) return #err("Not authorized");
    hydrateRuntimeStateIfNeeded();
    switch (nftListings.get(listingId)) {
      case null { return #err("Listing not found") };
      case (?listing) {
        let updated : NftListing = {
          id = listing.id; listingType = listing.listingType; name = listing.name;
          description = listing.description; rarity = listing.rarity; ticketCost = listing.ticketCost;
          imageUrl = listing.imageUrl; creator = listing.creator;
          tier = "jays-picks"; status = listing.status;
          feePaid = listing.feePaid; showroomFeePaid = listing.showroomFeePaid;
          txId = listing.txId; createdAt = listing.createdAt;
          sourceCanisterId = listing.sourceCanisterId; sourceTokenId = listing.sourceTokenId;
          sourceTokenKey = listing.sourceTokenKey; collectionName = listing.collectionName;
        };
        nftListings.put(listingId, updated);
        #ok("NFT promoted to Jay's Picks!");
      };
    };
  };

  /// Admin: remove NFT listing
  public shared(msg) func removeNftListing(listingId : Text) : async Result.Result<Text, Text> {
    assert (not isBannedNow(msg.caller)); // banned: only withdrawals, claims and listing allowed
    hydrateRuntimeStateIfNeeded();
    switch (nftListings.get(listingId)) {
      case null { return #err("Listing not found") };
      case (?listing) {
        if (not isAdmin(msg.caller) and not (listing.status == "pending_escrow" and Principal.equal(listing.creator, msg.caller))) return #err("Not authorized");
        let updated : NftListing = {
          id = listing.id; listingType = listing.listingType; name = listing.name;
          description = listing.description; rarity = listing.rarity; ticketCost = listing.ticketCost;
          imageUrl = listing.imageUrl; creator = listing.creator;
          tier = listing.tier; status = "removed";
          feePaid = listing.feePaid; showroomFeePaid = listing.showroomFeePaid;
          txId = listing.txId; createdAt = listing.createdAt;
          sourceCanisterId = listing.sourceCanisterId; sourceTokenId = listing.sourceTokenId;
          sourceTokenKey = listing.sourceTokenKey; collectionName = listing.collectionName;
        };
        nftListings.put(listingId, updated);
        #ok("NFT listing removed.");
      };
    };
  };

  /// Get admin-curated official arcade collections.
  public query func getOfficialCollections() : async [OfficialCollection] {
    let cols = if (runtimeStateHydrated) {
      Iter.toArray(officialCollections.vals());
    } else {
      Array.map<(Text, OfficialCollection), OfficialCollection>(officialCollectionEntries, func((_id, col)) { col });
    };
    Array.map<OfficialCollection, OfficialCollection>(cols, func(col) { withFreshCollectionAbilities(col) });
  };

  /// Get one admin-curated official arcade collection.
  public query func getOfficialCollection(collectionId : Text) : async ?OfficialCollection {
    let maybeCollection = if (runtimeStateHydrated) {
      officialCollections.get(collectionId);
    } else {
      findTextValue<OfficialCollection>(officialCollectionEntries, collectionId);
    };
    switch (maybeCollection) {
      case null { null };
      case (?collection) { ?withFreshCollectionAbilities(collection) };
    };
  };

  /// Admin: create an official collection shell from image URLs.
  public shared(msg) func adminCreateCollection(name : Text, description : Text, ticketCost : Nat, imageUrls : [Text]) : async Result.Result<Text, Text> {
    assert (not isBannedNow(msg.caller)); // banned: only withdrawals, claims and listing allowed
    if (not isAdmin(msg.caller)) return #err("Not authorized");
    if (Text.size(name) == 0) return #err("Collection name is required");
    if (imageUrls.size() == 0) return #err("At least one image URL is required");
    hydrateRuntimeStateIfNeeded();
    let id = genOfficialCollectionId();
    let collection : OfficialCollection = {
      id = id;
      name = name;
      description = description;
      creator = msg.caller;
      imageUrls = imageUrls;
      nftIds = [];
      ticketCost = ticketCost;
      totalSupply = imageUrls.size();
      abilities = [];
      createdAt = Time.now();
    };
    officialCollections.put(id, collection);
    #ok(id);
  };

  /// Admin: mint each image in an official collection into internal arcade listings.
  public shared(msg) func adminMintCollection(collectionId : Text) : async Result.Result<Text, Text> {
    assert (not isBannedNow(msg.caller)); // banned: only withdrawals, claims and listing allowed
    if (not isAdmin(msg.caller)) return #err("Not authorized");
    hydrateRuntimeStateIfNeeded();
    switch (officialCollections.get(collectionId)) {
      case null { #err("Collection not found") };
      case (?collection) {
        if (collection.nftIds.size() > 0) return #err("Collection already minted");
        if (nftCanisterIdText == "aaaaa-aa") return #err("NFT canister ID not configured — call adminSetNftCanisterId first");
        // Predict the real starting token ID (the canister assigns them sequentially from its
        // current total supply) so the on-chain metadata name matches the real token ID exactly,
        // not an artificial local counter that would drift for every collection after the first.
        let predictedStartId : Nat = await nftCanister().icrc7_total_supply();
        // Build metadata for each image, then mint the whole collection as one real ICRC-7 batch
        // into the Arcade's own custody (held here until a player redeems it with tickets).
        let metadataList = Buffer.Buffer<NftMetadata>(collection.imageUrls.size());
        var buildIdx : Nat = 0;
        for (imageUrl in collection.imageUrls.vals()) {
          let meta : NftMetadata = [
            ("name", #Text(collection.name # " #" # Nat.toText(predictedStartId + buildIdx))),
            ("image", #Text(imageUrl)),
            ("description", #Text(collection.description)),
            ("collection", #Text(collection.name)),
          ];
          metadataList.add(meta);
          buildIdx += 1;
        };
        let custody : Account = { owner = Principal.fromActor(ArcadeBackend); subaccount = null };
        let realTokenIds : [Nat] = await nftCanister().mintBatch(custody, Buffer.toArray(metadataList));
        if (realTokenIds.size() != collection.imageUrls.size()) return #err("Mint returned unexpected token count");
        let mintedIds = Buffer.Buffer<Nat>(collection.imageUrls.size());
        var mintedCount : Nat = 0;
        for (imageUrl in collection.imageUrls.vals()) {
          let listingId = genListingId("official");
          let realTokenId = realTokenIds[mintedCount];
          let listing : NftListing = {
            id = listingId;
            listingType = "mint";
            name = collection.name # " #" # Nat.toText(realTokenId);
            description = collection.description;
            rarity = "official";
            ticketCost = collection.ticketCost;
            imageUrl = imageUrl;
            creator = msg.caller;
            tier = "open";
            status = "live";
            feePaid = 0;
            showroomFeePaid = 0;
            txId = realTokenId;
            createdAt = Time.now();
            sourceCanisterId = nftCanisterIdText;
            sourceTokenId = realTokenId;
            sourceTokenKey = "official:" # collection.id # ":" # Nat.toText(realTokenId);
            collectionName = collection.name;
          };
          nftListings.put(listingId, listing);
          mintedIds.add(realTokenId);
          mintedCount += 1;
        };
        let updated : OfficialCollection = {
          id = collection.id;
          name = collection.name;
          description = collection.description;
          creator = collection.creator;
          imageUrls = collection.imageUrls;
          nftIds = Buffer.toArray(mintedIds);
          ticketCost = collection.ticketCost;
          totalSupply = collection.totalSupply;
          abilities = collection.abilities;
          createdAt = collection.createdAt;
        };
        putOfficialCollection(updated);
        #ok("Minted " # Nat.toText(mintedCount) # " official NFTs on-chain (nft_canister " # nftCanisterIdText # ")");
      };
    };
  };

  /// Admin: delete an unminted official collection.
  public shared(msg) func adminDeleteCollection(collectionId : Text) : async Result.Result<Bool, Text> {
    assert (not isBannedNow(msg.caller)); // banned: only withdrawals, claims and listing allowed
    if (not isAdmin(msg.caller)) return #err("Not authorized");
    hydrateRuntimeStateIfNeeded();
    switch (officialCollections.get(collectionId)) {
      case null { #err("Collection not found") };
      case (?collection) {
        if (collection.nftIds.size() > 0) return #err("Cannot delete a minted collection");
        officialCollections.delete(collectionId);
        #ok(true);
      };
    };
  };

  /// Backward-compatible alias for admin UI callsites that use the shorter name.
  public shared(msg) func adminDeleteCol(collectionId : Text) : async Result.Result<Bool, Text> {
    assert (not isBannedNow(msg.caller)); // banned: only withdrawals, claims and listing allowed
    await adminDeleteCollection(collectionId);
  };

  /// Get token ability assignments for one official collection.
  public shared query(msg) func adminGetCollectionTokenAbilities(collectionId : Text) : async [(Nat, Text)] {
    if (not isAdmin(msg.caller)) return []; // abilities are secret: admin only
    let maybeCollection = if (runtimeStateHydrated) {
      officialCollections.get(collectionId);
    } else {
      findTextValue<OfficialCollection>(officialCollectionEntries, collectionId);
    };
    switch (maybeCollection) {
      case null { [] };
      case (?collection) {
        let abilityEntries = if (runtimeStateHydrated) { Iter.toArray(officialCollectionAbilities.entries()) } else { officialCollectionAbilityEntries };
        let buf = Buffer.Buffer<(Nat, Text)>(collection.nftIds.size());
        for (tokenId in collection.nftIds.vals()) {
          for ((abilityTokenId, ability) in abilityEntries.vals()) {
            if (abilityTokenId == tokenId) buf.add((tokenId, ability));
          };
        };
        Buffer.toArray(buf);
      };
    };
  };

  public query func getNftAbilities(tokenId : Nat) : async [(Text, Text)] {
    let ability = if (runtimeStateHydrated) { officialCollectionAbilities.get(tokenId) } else { findNatText(officialCollectionAbilityEntries, tokenId) };
    switch (ability) {
      case null { [] };
      case (?a) { [("ability", a)] };
    };
  };

  public query func getDisabledAbilities() : async [Text] {
    if (runtimeStateHydrated) {
      Iter.toArray(disabledAbilities.keys());
    } else {
      disabledAbilityEntries;
    };
  };

  public shared(msg) func adminAssignAbility(tokenId : Nat, ability : Text) : async Result.Result<Text, Text> {
    assert (not isBannedNow(msg.caller)); // banned: only withdrawals, claims and listing allowed
    if (not isAdmin(msg.caller)) return #err("Not authorized");
    if (Text.size(ability) == 0) return #err("Ability is required");
    hydrateRuntimeStateIfNeeded();
    if (not tokenBelongsToOfficialCollection(tokenId)) return #err("Official collection token not found");
    officialCollectionAbilities.put(tokenId, ability);
    for ((collectionId, collection) in officialCollections.entries()) {
      if (collectionContainsToken(collection, tokenId)) {
        putOfficialCollection(collection);
      };
    };
    #ok("Ability assigned");
  };

  public shared(msg) func adminSetCollectionTokenAbility(collectionId : Text, tokenId : Nat, ability : Text) : async Result.Result<Text, Text> {
    assert (not isBannedNow(msg.caller)); // banned: only withdrawals, claims and listing allowed
    if (not isAdmin(msg.caller)) return #err("Not authorized");
    hydrateRuntimeStateIfNeeded();
    switch (officialCollections.get(collectionId)) {
      case null { #err("Collection not found") };
      case (?collection) {
        if (not collectionContainsToken(collection, tokenId)) return #err("Token is not in this collection");
        officialCollectionAbilities.put(tokenId, ability);
        putOfficialCollection(collection);
        #ok("Ability assigned");
      };
    };
  };

  public shared(msg) func adminBatchAssignAbilities(assignments : [(Nat, Text)]) : async Result.Result<Text, Text> {
    assert (not isBannedNow(msg.caller)); // banned: only withdrawals, claims and listing allowed
    if (not isAdmin(msg.caller)) return #err("Not authorized");
    hydrateRuntimeStateIfNeeded();
    var assigned : Nat = 0;
    for ((tokenId, ability) in assignments.vals()) {
      if (Text.size(ability) > 0 and tokenBelongsToOfficialCollection(tokenId)) {
        officialCollectionAbilities.put(tokenId, ability);
        assigned += 1;
      };
    };
    for ((_collectionId, collection) in officialCollections.entries()) {
      putOfficialCollection(collection);
    };
    #ok("Assigned " # Nat.toText(assigned) # " abilities");
  };

  public shared(msg) func adminRemoveAbility(tokenId : Nat) : async Result.Result<Text, Text> {
    assert (not isBannedNow(msg.caller)); // banned: only withdrawals, claims and listing allowed
    if (not isAdmin(msg.caller)) return #err("Not authorized");
    hydrateRuntimeStateIfNeeded();
    if (not tokenBelongsToOfficialCollection(tokenId)) return #err("Official collection token not found");
    officialCollectionAbilities.delete(tokenId);
    for ((_collectionId, collection) in officialCollections.entries()) {
      if (collectionContainsToken(collection, tokenId)) {
        putOfficialCollection(collection);
      };
    };
    #ok("Ability removed");
  };

  public shared(msg) func adminClearCollectionTokenAbility(collectionId : Text, tokenId : Nat) : async Result.Result<Text, Text> {
    assert (not isBannedNow(msg.caller)); // banned: only withdrawals, claims and listing allowed
    if (not isAdmin(msg.caller)) return #err("Not authorized");
    hydrateRuntimeStateIfNeeded();
    switch (officialCollections.get(collectionId)) {
      case null { #err("Collection not found") };
      case (?collection) {
        if (not collectionContainsToken(collection, tokenId)) return #err("Token is not in this collection");
        officialCollectionAbilities.delete(tokenId);
        putOfficialCollection(collection);
        #ok("Ability removed");
      };
    };
  };

  // === OFFICIAL NFT ABILITIES (phase 1: foundation) ===
  // Secret by design: assignments are only readable through admin-only queries. Collection abilities live in
  // collectionAbilityEntries (collection id -> [(id, value)]) - NOT OfficialCollection.abilities, which putOfficialCollection
  // rebuilds from the per-token map on every save. Per-NFT extras live in officialCollectionAbilities as "id|id=value".
  // A player's abilities = for every Official NFT they hold (not held in arcade escrow): collection + token abilities.
  transient let ABILITY_IDS : [Text] = ["gxp-amp", "mxp-amp", "dxp-amp", "token-lottery", "ticket-lottery", "vp-plus",
    "access-dev", "access-art", "access-veteran", "access-elite", "access-diplomat", "access-all",
    "border-rainbow", "border-diamond", "border-gold", "border-whitelight",
    "neon-name", "collector-title", "forum-thread-plus", "proposal-plus"];
  func isKnownAbility(id : Text) : Bool { for (a in ABILITY_IDS.vals()) { if (a == id) return true }; false };
  // Normalised (trimmed, lowercased) so escrow canister ids typed or passed in a different form still match.
  func isOfficialNftCanister(c : Text) : Bool {
    Text.toLowercase(Text.trim(c, #char ' ')) == Text.toLowercase(Text.trim(nftCanisterIdText, #char ' '))
  };

  stable var officialNftOwnerEntries : [(Nat, Principal)] = [];
  stable var collectionAbilityEntries : [(Text, [(Text, Text)])] = [];
  func collectionAbilitiesOf(collectionId : Text) : [(Text, Text)] {
    for ((k, l) in collectionAbilityEntries.vals()) { if (k == collectionId) return l };
    []
  };
  func setCollectionAbilitiesStore(collectionId : Text, list : [(Text, Text)]) {
    let rest = Array.filter<(Text, [(Text, Text)])>(collectionAbilityEntries, func(e) { e.0 != collectionId });
    collectionAbilityEntries := if (list.size() == 0) { rest } else { Array.append<(Text, [(Text, Text)])>(rest, [(collectionId, list)]) };
  };
  func officialOwnerOf(t : Nat) : ?Principal {
    for ((k, o) in officialNftOwnerEntries.vals()) { if (k == t) return ?o };
    null
  };
  func setOfficialOwner(t : Nat, owner : ?Principal) {
    let rest = Array.filter<(Nat, Principal)>(officialNftOwnerEntries, func(e) { e.0 != t });
    officialNftOwnerEntries := switch (owner) { case (?o) { Array.append<(Nat, Principal)>(rest, [(t, o)]) }; case null { rest } };
  };
  func tokenHeldInArcadeEscrow(t : Nat) : Bool {
    let tt = Nat.toText(t);
    for (e in escrows.vals()) { if (isOfficialNftCanister(e.canisterId) and e.tokenId == tt and e.status == "held") return true };
    false
  };
  func collectionOfOfficialToken(t : Nat) : ?OfficialCollection {
    for (c in officialCollections.vals()) { if (collectionContainsToken(c, t)) return ?c };
    null
  };
  func parseAbilityText(raw : Text) : [(Text, Text)] {
    let out = Buffer.Buffer<(Text, Text)>(4);
    for (part in Text.split(raw, #char '|')) {
      let kv = Iter.toArray(Text.split(part, #char '='));
      if (kv.size() > 0) {
        let id = Text.trim(kv[0], #char ' ');
        if (isKnownAbility(id)) { out.add((id, if (kv.size() > 1) { Text.trim(kv[1], #char ' ') } else { "" })) };
      };
    };
    Buffer.toArray(out)
  };
  func encodeAbilityList(list : [(Text, Text)]) : Text {
    var t = "";
    for ((id, v) in list.vals()) {
      let piece = if (v == "") { id } else { id # "=" # v };
      t := if (t == "") { piece } else { t # "|" # piece };
    };
    t
  };
  func cleanAbilityList(list : [(Text, Text)]) : Result.Result<[(Text, Text)], Text> {
    let out = Buffer.Buffer<(Text, Text)>(list.size());
    for ((id, v) in list.vals()) {
      if (not isKnownAbility(id)) return #err("Unknown ability: " # id);
      if (Text.size(v) > 40) return #err("Ability value too long (max 40): " # id);
      if (Text.contains(v, #char '|') or Text.contains(v, #char '=')) return #err("Ability values can't contain | or =");
      out.add((id, v));
    };
    #ok(Buffer.toArray(out))
  };
  // Every ability instance a player holds right now (duplicates = stacking).
  func abilityInstancesOf(p : Principal) : [(Text, Text)] {
    hydrateRuntimeStateIfNeeded();
    if (isBannedNow(p)) return [];
    let out = Buffer.Buffer<(Text, Text)>(8);
    for ((t, o) in officialNftOwnerEntries.vals()) {
      if (Principal.equal(o, p) and not tokenHeldInArcadeEscrow(t)) {
        switch (collectionOfOfficialToken(t)) {
          case (?c) { for ((id, v) in collectionAbilitiesOf(c.id).vals()) { if (isKnownAbility(id) and disabledAbilities.get(id) == null) { out.add((id, v)) } } };
          case null {};
        };
        switch (officialCollectionAbilities.get(t)) {
          case (?raw) { for ((id, v) in parseAbilityText(raw).vals()) { if (disabledAbilities.get(id) == null) { out.add((id, v)) } } };
          case null {};
        };
      };
    };
    Buffer.toArray(out)
  };
  func abilityCountOf(p : Principal, id : Text) : Nat {
    var n : Nat = 0;
    for ((a, _) in abilityInstancesOf(p).vals()) { if (a == id) { n += 1 } };
    n
  };
  func abilityValueOf(p : Principal, id : Text) : ?Text {
    for ((a, v) in abilityInstancesOf(p).vals()) { if (a == id) return ?v };
    null
  };

  // === NFT game perk tags (not secret). Games read them, plus GXP/DXP/MXP, via getMyGamePerks. ===
  stable var collectionPerkTagEntries : [(Text, [Text])] = [];
  stable var tokenPerkTagEntries : [(Nat, [Text])] = [];
  func cleanPerkTags(list : [Text]) : Result.Result<[Text], Text> {
    if (list.size() > 10) return #err("At most 10 tags");
    let b = Buffer.Buffer<Text>(list.size());
    for (raw in list.vals()) {
      let t = Text.trim(raw, #char ' ');
      if (t != "") {
        if (Text.size(t) > 32) return #err("Tag too long (max 32 characters): " # t);
        for (c in t.chars()) {
          if (not ((c >= 'a' and c <= 'z') or (c >= '0' and c <= '9') or c == '-')) return #err("Tags may only use a-z, 0-9 and dashes: " # t);
        };
        var dup = false;
        for (x in b.vals()) { if (x == t) { dup := true } };
        if (not dup) { b.add(t) };
      };
    };
    #ok(Buffer.toArray(b))
  };
  // Official collection name -> perk tag: lowercase letters/numbers, other runs become one dash, max 32 chars.
  func perkSlug(name : Text) : Text {
    var out = "";
    var dash = false;
    for (c in Text.toLowercase(name).chars()) {
      if ((c >= 'a' and c <= 'z') or (c >= '0' and c <= '9')) {
        if (dash and out != "") { out #= "-" };
        out #= Text.fromChar(c);
        dash := false;
      } else { dash := true };
    };
    if (Text.size(out) <= 32) return out;
    var r = "";
    var n : Nat = 0;
    for (c in out.chars()) { if (n < 32) { r #= Text.fromChar(c) }; n += 1 };
    r
  };
  func collectionPerkTagsOf(colId : Text) : [Text] {
    for ((k, v) in collectionPerkTagEntries.vals()) { if (k == colId) return v };
    []
  };
  func tokenPerkTagsOf(t : Nat) : [Text] {
    for ((k, v) in tokenPerkTagEntries.vals()) { if (k == t) return v };
    []
  };
  public shared(msg) func adminSetCollectionPerkTags(collectionId : Text, tags : [Text]) : async Result.Result<Text, Text> {
    if (not isAdmin(msg.caller)) return #err("Admin only");
    hydrateRuntimeStateIfNeeded();
    let clean = switch (cleanPerkTags(tags)) { case (#ok(l)) { l }; case (#err(e)) { return #err(e) } };
    switch (officialCollections.get(collectionId)) {
      case null { #err("Collection not found") };
      case (?c) {
        for (tg in clean.vals()) {
          var known = false;
          for (oc in officialCollections.vals()) { if (perkSlug(oc.name) == tg) { known := true } };
          if (not known) return #err("Perk tags must be an Official collection's tag: " # tg);
        };
        let rest = Array.filter<(Text, [Text])>(collectionPerkTagEntries, func(e) { e.0 != c.id });
        collectionPerkTagEntries := if (clean.size() == 0) { rest } else { Array.append<(Text, [Text])>(rest, [(c.id, clean)]) };
        #ok("Collection perk tags saved (" # Nat.toText(clean.size()) # ")")
      };
    }
  };
  public shared(msg) func adminSetTokenPerkTags(tokenId : Nat, tags : [Text]) : async Result.Result<Text, Text> {
    if (not isAdmin(msg.caller)) return #err("Admin only");
    hydrateRuntimeStateIfNeeded();
    if (not tokenBelongsToOfficialCollection(tokenId)) return #err("Official collection token not found");
    let clean = switch (cleanPerkTags(tags)) { case (#ok(l)) { l }; case (#err(e)) { return #err(e) } };
    for (tg in clean.vals()) { if (tg != "gold") return #err("Only Gold status can be set per NFT") };
    let rest = Array.filter<(Nat, [Text])>(tokenPerkTagEntries, func(e) { e.0 != tokenId });
    tokenPerkTagEntries := if (clean.size() == 0) { rest } else { Array.append<(Nat, [Text])>(rest, [(tokenId, clean)]) };
    #ok("NFT perk tags saved (" # Nat.toText(clean.size()) # ")")
  };
  public shared query(msg) func adminGetCollectionPerkTags(collectionId : Text) : async { collection : [Text]; tokens : [(Nat, [Text])] } {
    if (not isAdmin(msg.caller)) return { collection = []; tokens = [] };
    let toks = Buffer.Buffer<(Nat, [Text])>(8);
    for ((t, tags) in tokenPerkTagEntries.vals()) {
      switch (collectionOfOfficialToken(t)) { case (?c) { if (c.id == collectionId) { toks.add((t, tags)) } }; case null {} };
    };
    { collection = collectionPerkTagsOf(collectionId); tokens = Buffer.toArray(toks) }
  };
  // Asked by the signed-in player (via the arcade). Tags come from Official NFTs they hold that are not listed in escrow.
  public shared query(msg) func getMyGamePerks() : async { tags : [Text]; gxp : Nat; dxp : Nat; mxp : Nat } {
    let p = msg.caller;
    if (Principal.isAnonymous(p) or isBannedNow(p)) return { tags = []; gxp = 0; dxp = 0; mxp = 0 };
    hydrateRuntimeStateIfNeeded();
    let out = Buffer.Buffer<Text>(8);
    func addTag(t : Text) { for (x in out.vals()) { if (x == t) return }; out.add(t) };
    for ((t, o) in officialNftOwnerEntries.vals()) {
      if (Principal.equal(o, p) and not tokenHeldInArcadeEscrow(t)) {
        switch (collectionOfOfficialToken(t)) { case (?c) { for (x in collectionPerkTagsOf(c.id).vals()) { addTag(x) } }; case null {} };
        for (x in tokenPerkTagsOf(t).vals()) {
          if (x == "gold") {
            switch (collectionOfOfficialToken(t)) { case (?c) { for (y in collectionPerkTagsOf(c.id).vals()) { addTag(y # "-gold") } }; case null {} };
          } else { addTag(x) };
        };
      };
    };
    let g : Nat = switch (gxp.get(p)) { case (?v) { v }; case null { 0 } };
    let d : Nat = switch (dxp.get(p)) { case (?v) { v }; case null { 0 } };
    let m : Nat = switch (mxp.get(p)) { case (?v) { v }; case null { 0 } };
    { tags = Buffer.toArray(out); gxp = g; dxp = d; mxp = m }
  };

  public shared(msg) func adminSetCollectionAbilities(collectionId : Text, list : [(Text, Text)]) : async Result.Result<Text, Text> {
    assert (not isBannedNow(msg.caller)); // banned: only withdrawals, claims and listing allowed
    if (not isAdmin(msg.caller)) return #err("Admin only");
    hydrateRuntimeStateIfNeeded();
    let clean = switch (cleanAbilityList(list)) { case (#ok(l)) { l }; case (#err(e)) { return #err(e) } };
    switch (officialCollections.get(collectionId)) {
      case null { #err("Collection not found") };
      case (?c) { setCollectionAbilitiesStore(c.id, clean); #ok("Collection abilities saved (" # Nat.toText(clean.size()) # ")") };
    }
  };
  public shared(msg) func adminSetTokenAbilities(tokenId : Nat, list : [(Text, Text)]) : async Result.Result<Text, Text> {
    assert (not isBannedNow(msg.caller)); // banned: only withdrawals, claims and listing allowed
    if (not isAdmin(msg.caller)) return #err("Admin only");
    hydrateRuntimeStateIfNeeded();
    if (not tokenBelongsToOfficialCollection(tokenId)) return #err("Official collection token not found");
    let clean = switch (cleanAbilityList(list)) { case (#ok(l)) { l }; case (#err(e)) { return #err(e) } };
    if (clean.size() == 0) { officialCollectionAbilities.delete(tokenId) } else { officialCollectionAbilities.put(tokenId, encodeAbilityList(clean)) };
    #ok("NFT abilities saved (" # Nat.toText(clean.size()) # ")")
  };
  public shared(msg) func adminSyncOfficialOwners() : async Result.Result<Text, Text> {
    assert (not isBannedNow(msg.caller)); // banned: only withdrawals, claims and listing allowed
    if (not isAdmin(msg.caller)) return #err("Admin only");
    hydrateRuntimeStateIfNeeded();
    let self = Principal.fromActor(ArcadeBackend);
    let ids = Buffer.Buffer<Nat>(64);
    for (c in officialCollections.vals()) { for (t in c.nftIds.vals()) { ids.add(t) } };
    var players : Nat = 0; var arcade : Nat = 0; var failed : Nat = 0;
    for (t in ids.vals()) {
      try {
        switch (await nftCanister().icrc7_owner_of(t)) {
          case (#Ok(acc)) {
            if (Principal.equal(acc.owner, self)) { setOfficialOwner(t, null); arcade += 1 } else { setOfficialOwner(t, ?acc.owner); players += 1 };
          };
          case (#Err(_)) { failed += 1 };
        };
      } catch (_) { failed += 1 };
    };
    #ok("Synced: " # Nat.toText(players) # " player-held, " # Nat.toText(arcade) # " arcade-held, " # Nat.toText(failed) # " failed")
  };
  // === Cosmetics come ONLY from the Official NFT a player wears as their PFP (functional abilities still stack). ===
  stable var pfpNftEntries : [(Principal, Nat)] = [];
  func pfpNftOf(p : Principal) : ?Nat {
    for ((k, t) in pfpNftEntries.vals()) { if (Principal.equal(k, p)) return ?t };
    null
  };
  func setPfpNftEntry(p : Principal, t : ?Nat) {
    let rest = Array.filter<(Principal, Nat)>(pfpNftEntries, func(e) { not Principal.equal(e.0, p) });
    pfpNftEntries := switch (t) { case (?x) { Array.append<(Principal, Nat)>(rest, [(p, x)]) }; case null { rest } };
  };
  // One token's abilities: its collection-wide abilities plus its own extras (disabled ones skipped).
  func abilitiesOfToken(t : Nat) : [(Text, Text)] {
    let out = Buffer.Buffer<(Text, Text)>(4);
    switch (collectionOfOfficialToken(t)) {
      case (?c) { for ((id, v) in collectionAbilitiesOf(c.id).vals()) { if (isKnownAbility(id) and disabledAbilities.get(id) == null) { out.add((id, v)) } } };
      case null {};
    };
    switch (officialCollectionAbilities.get(t)) {
      case (?raw) { for ((id, v) in parseAbilityText(raw).vals()) { if (disabledAbilities.get(id) == null) { out.add((id, v)) } } };
      case null {};
    };
    Buffer.toArray(out)
  };
  func cosmeticSourceOf(p : Principal) : [(Text, Text)] {
    if (isBannedNow(p)) return [];
    switch (pfpNftOf(p)) {
      case (?t) { if (officialOwnerOf(t) == ?p and not tokenHeldInArcadeEscrow(t)) { abilitiesOfToken(t) } else { [] } };
      case null { [] };
    }
  };
  public shared(msg) func setMyPfpNft(tokenId : ?Nat) : async Result.Result<Text, Text> {
    assert (not isBannedNow(msg.caller)); // banned: only withdrawals, claims and listing allowed
    let caller = msg.caller;
    if (Principal.isAnonymous(caller)) return #err("Must be authenticated");
    hydrateRuntimeStateIfNeeded();
    switch (tokenId) {
      case null { setPfpNftEntry(caller, null); #ok("PFP NFT cleared") };
      case (?t) {
        if (not tokenBelongsToOfficialCollection(t)) { setPfpNftEntry(caller, null); return #ok("Not an Official NFT - no cosmetics") };
        if (officialOwnerOf(t) != ?caller or tokenHeldInArcadeEscrow(t)) { setPfpNftEntry(caller, null); return #err("You don't currently hold that Official NFT") };
        setPfpNftEntry(caller, ?t);
        #ok("PFP NFT set")
      };
    }
  };

  // Public cosmetics: the visible EFFECT only (border / neon colour / title), never which NFT grants it.
  public query func getCosmetics(players : [Principal]) : async [(Principal, { border : Text; neon : Text; title : Text })] {
    hydrateRuntimeStateIfNeeded();
    let out = Buffer.Buffer<(Principal, { border : Text; neon : Text; title : Text })>(players.size());
    var n : Nat = 0;
    label scan for (p in players.vals()) {
      if (n >= 60) break scan;
      n += 1;
      var rank : Nat = 0; var neon = ""; var title = "";
      for ((a, v) in cosmeticSourceOf(p).vals()) {
        let r : Nat = if (a == "border-whitelight") 4 else if (a == "border-rainbow") 3 else if (a == "border-diamond") 2 else if (a == "border-gold") 1 else 0;
        if (r > rank) { rank := r };
        if (a == "neon-name" and neon == "") { neon := if (v == "") "#ff3cac" else v };
        if (a == "collector-title" and title == "" and v != "") { title := v };
      };
      let border = if (rank == 4) "whitelight" else if (rank == 3) "rainbow" else if (rank == 2) "diamond" else if (rank == 1) "gold" else "";
      if (border != "" or neon != "" or title != "") { out.add((p, { border = border; neon = neon; title = title })) };
    };
    Buffer.toArray(out)
  };
  public shared query(msg) func getMyPerks() : async { vp : Nat; access : [Text]; wallSlots : Nat; forumThreads : Nat; proposals : Nat; gxpAmp : Nat; mxpAmp : Nat; dxpAmp : Nat; tokenLottery : Nat; ticketLottery : Nat } {
    var vp : Nat = 0; var wall : Nat = 0; var ft : Nat = 0; var pr : Nat = 0; var ga : Nat = 0; var ma : Nat = 0; var da : Nat = 0; var tl : Nat = 0; var kl : Nat = 0;
    let acc = Buffer.Buffer<Text>(4);
    if (not isAnonymousPrincipal(msg.caller)) {
      for ((a, _) in abilityInstancesOf(msg.caller).vals()) {
        if (a == "vp-plus") { vp += 1 } else if (a == "wall-plus") { wall += 1 } else if (a == "forum-thread-plus") { ft += 1 }
        else if (a == "proposal-plus") { pr += 1 } else if (a == "gxp-amp") { ga += 1 } else if (a == "mxp-amp") { ma += 1 }
        else if (a == "dxp-amp") { da += 1 } else if (a == "token-lottery") { tl += 1 } else if (a == "ticket-lottery") { kl += 1 }
        else if (Text.startsWith(a, #text "access-")) { var dup = false; for (x in acc.vals()) { if (x == a) { dup := true } }; if (not dup) { acc.add(a) } };
      };
    };
    { vp = vp; access = Buffer.toArray(acc); wallSlots = 5 + wall; forumThreads = 1 + ft; proposals = 1 + pr; gxpAmp = ga; mxpAmp = ma; dxpAmp = da; tokenLottery = tl; ticketLottery = kl }
  };
  public shared query(msg) func adminGetPlayerAbilities(p : Principal) : async [(Text, Text)] {
    if (not isAdmin(msg.caller)) return [];
    abilityInstancesOf(p)
  };
  public shared query(msg) func adminGetCollectionAbilitySetup(collectionId : Text) : async { collection : [(Text, Text)]; tokens : [(Nat, [(Text, Text)])] } {
    if (not isAdmin(msg.caller)) return { collection = []; tokens = [] };
    switch (officialCollections.get(collectionId)) {
      case null { { collection = []; tokens = [] } };
      case (?c) {
        let toks = Buffer.Buffer<(Nat, [(Text, Text)])>(c.nftIds.size());
        for (t in c.nftIds.vals()) {
          switch (officialCollectionAbilities.get(t)) { case (?raw) { toks.add((t, parseAbilityText(raw))) }; case null {} };
        };
        { collection = collectionAbilitiesOf(c.id); tokens = Buffer.toArray(toks) }
      };
    }
  };

  public shared(msg) func adminDisableAbility(ability : Text) : async Result.Result<Text, Text> {
    assert (not isBannedNow(msg.caller)); // banned: only withdrawals, claims and listing allowed
    if (not isAdmin(msg.caller)) return #err("Not authorized");
    hydrateRuntimeStateIfNeeded();
    disabledAbilities.put(ability, true);
    #ok("Ability disabled");
  };

  public shared(msg) func adminEnableAbility(ability : Text) : async Result.Result<Text, Text> {
    assert (not isBannedNow(msg.caller)); // banned: only withdrawals, claims and listing allowed
    if (not isAdmin(msg.caller)) return #err("Not authorized");
    hydrateRuntimeStateIfNeeded();
    disabledAbilities.delete(ability);
    #ok("Ability enabled");
  };

  /// Get all live NFT listings
  public query func getNftListings() : async [NftListing] {
    let all = if (runtimeStateHydrated) {
      Iter.toArray(nftListings.vals());
    } else {
      Array.map<(Text, NftListingStable), NftListing>(nftListingEntries, func((listingId, listing)) { hydrateNftListing(listingId, listing) });
    };
    Array.filter<NftListing>(all, func(l) { l.status == "live" });
  };

  /// Get NFT listings by tier
  public query func getNftListingsByTier(tier : Text) : async [NftListing] {
    let all = if (runtimeStateHydrated) {
      Iter.toArray(nftListings.vals());
    } else {
      Array.map<(Text, NftListingStable), NftListing>(nftListingEntries, func((listingId, listing)) { hydrateNftListing(listingId, listing) });
    };
    Array.filter<NftListing>(all, func(l) { l.status == "live" and l.tier == tier });
  };

  /// Get a single NFT listing
  public query func getNftListing(listingId : Text) : async ?NftListing {
    if (runtimeStateHydrated) {
      nftListings.get(listingId);
    } else {
      switch (findTextValue<NftListingStable>(nftListingEntries, listingId)) {
        case (?stableListing) { ?hydrateNftListing(listingId, stableListing) };
        case null { null };
      };
    };
  };

  /// Get NFT listings by creator
  public query func getMyNftListings(creator : Principal) : async [NftListing] {
    let all = if (runtimeStateHydrated) {
      Iter.toArray(nftListings.vals());
    } else {
      Array.map<(Text, NftListingStable), NftListing>(nftListingEntries, func((listingId, listing)) { hydrateNftListing(listingId, listing) });
    };
    Array.filter<NftListing>(all, func(l) { Principal.equal(l.creator, creator) });
  };

  /// Caller-scoped NFT listing limits consumed by the frontend before escrow transfer.
  /// Keep this query present whenever frontend IDL exposes getMyNftLimitStatus; missing it blocks safe listing before any NFT moves.
  public shared query(msg) func getMyNftLimitStatus() : async {
    activeListings : Nat;
    activeListingsCap : Nat;
    mintedCount : Nat;
    mintedCap : Nat;
  } {
    let caller = msg.caller;
    let all = if (runtimeStateHydrated) {
      Iter.toArray(nftListings.vals());
    } else {
      Array.map<(Text, NftListingStable), NftListing>(nftListingEntries, func((listingId, listing)) { hydrateNftListing(listingId, listing) });
    };
    var activeListings : Nat = 0;
    var mintedCount : Nat = 0;
    if (not Principal.isAnonymous(caller)) {
      for (listing in all.vals()) {
        if (Principal.equal(listing.creator, caller)) {
          // Only a user's own "existing" (user-sourced) listings count toward their personal
          // active-listing cap, and only while genuinely occupying marketplace space (live or
          // pending escrow) — an official collection mint isn't "your own listing", and a
          // successfully sold item is no longer occupying anything.
          if (listing.listingType != "mint" and (listing.status == "live" or listing.status == "pending_escrow")) {
            activeListings += 1;
          };
          if (listing.listingType == "mint") {
            mintedCount += 1;
          };
        };
      };
    };
    {
      activeListings = activeListings;
      activeListingsCap = 25;
      mintedCount = mintedCount;
      mintedCap = 100;
    };
  };

  /// Returns the caller's own currently-active listings (user-sourced "existing" listings only,
  /// live or pending escrow) — used so a listed NFT can still show as "in Prize Booth" in the
  /// owner's My Collection view, even though they no longer hold it on-chain.
  public shared query(msg) func getMyActiveNftListings() : async [NftListing] {
    let caller = msg.caller;
    if (Principal.isAnonymous(caller)) return [];
    let all = if (runtimeStateHydrated) {
      Iter.toArray(nftListings.vals());
    } else {
      Array.map<(Text, NftListingStable), NftListing>(nftListingEntries, func((listingId, listing)) { hydrateNftListing(listingId, listing) });
    };
    Array.filter<NftListing>(all, func(listing) {
      Principal.equal(listing.creator, caller) and
      listing.listingType != "mint" and
      (listing.status == "live" or listing.status == "pending_escrow")
    });
  };

  /// GXP: soulbound Game Experience stat for a given player. Only increases, no admin override.
  public query func getGxp(player : Principal) : async Nat {
    getGxpBalance(player);
  };

  /// The site-wide highest GXP ever reached by any single player, for scaling a display color.
  public query func getMaxGxp() : async Nat {
    maxGxpEverSeen;
  };

  /// DXP: soulbound DAO Experience stat for a given player. Only increases, no admin override.
  public query func getDxp(player : Principal) : async Nat {
    getDxpBalance(player);
  };

  /// The site-wide highest DXP ever reached by any single player, for scaling a display color.
  public query func getMaxDxp() : async Nat {
    maxDxpEverSeen;
  };

  /// MXP: soulbound Market Experience stat for a given player. Only increases, no admin override.
  public query func getMxp(player : Principal) : async Nat {
    getMxpBalance(player);
  };

  /// The site-wide highest MXP ever reached by any single player, for scaling a display color.
  public query func getMaxMxp() : async Nat {
    maxMxpEverSeen;
  };

  /// Save the caller's own real on-chain profile (name/bio/avatar), visible to anyone via
  /// getPlayerProfile — previously this call existed in the frontend but not the backend at all.
  // === Ban system: banned players can only withdraw ICP, claim earnings and list NFTs (fee still charged). ===
  stable var bannedEntries : [(Principal, Text, Int, Int)] = []; // (player, reason, until (0 = permanent), bannedAt)
  func banEntryOf(p : Principal) : ?(Principal, Text, Int, Int) {
    for (e in bannedEntries.vals()) { if (Principal.equal(e.0, p)) return ?e };
    null
  };
  func isBannedNow(p : Principal) : Bool {
    switch (banEntryOf(p)) { case null { false }; case (?e) { e.2 == 0 or Time.now() < e.2 } }
  };
  func setBanEntry(p : Principal, e : ?(Principal, Text, Int, Int)) {
    let rest = Array.filter<(Principal, Text, Int, Int)>(bannedEntries, func(x) { not Principal.equal(x.0, p) });
    bannedEntries := switch (e) { case (?v) { Array.append<(Principal, Text, Int, Int)>(rest, [v]) }; case null { rest } };
  };
  func banPlayer(caller : Principal, p : Principal, reason : Text, durationDays : Nat) : Result.Result<Text, Text> {
    if (not isAdmin(caller)) return #err("Not authorized");
    if (isAdmin(p)) return #err("Admins can't be banned");
    if (Principal.isAnonymous(p)) return #err("Invalid principal");
    if (Text.size(reason) > 300) return #err("Reason too long (max 300 characters)");
    let until : Int = if (durationDays == 0) { 0 } else { Time.now() + durationDays * 86_400_000_000_000 };
    setBanEntry(p, ?(p, reason, until, Time.now()));
    #ok(if (durationDays == 0) { "Banned permanently" } else { "Banned for " # Nat.toText(durationDays) # " day(s)" })
  };
  public shared(msg) func adminBanUserFor(p : Principal, reason : Text, durationDays : Nat) : async Result.Result<Text, Text> {
    banPlayer(msg.caller, p, reason, durationDays)
  };
  // Legacy entry point (existing admin button): permanent ban.
  public shared(msg) func adminBanUser(p : Principal, banType : Text, reason : Text) : async Result.Result<Text, Text> {
    ignore banType;
    banPlayer(msg.caller, p, reason, 0)
  };
  public shared(msg) func adminUnbanUser(p : Principal) : async Result.Result<Text, Text> {
    if (not isAdmin(msg.caller)) return #err("Not authorized");
    setBanEntry(p, null);
    #ok("Unbanned")
  };
  public shared query(msg) func getBannedUsers() : async [(Principal, Text, Text, Int)] {
    if (not isAdmin(msg.caller)) return [];
    let out = Buffer.Buffer<(Principal, Text, Text, Int)>(bannedEntries.size());
    for (e in bannedEntries.vals()) {
      if (e.2 == 0 or Time.now() < e.2) { out.add((e.0, if (e.2 == 0) { "permanent" } else { "timed" }, e.1, e.2)) };
    };
    Buffer.toArray(out)
  };
  public query func checkBanStatus(p : Principal) : async { banned : Bool; banType : Text; reason : Text; until : Int } {
    switch (banEntryOf(p)) {
      case (?e) { if (e.2 == 0 or Time.now() < e.2) { return { banned = true; banType = "soft"; reason = e.1; until = e.2 } } };
      case null {};
    };
    { banned = false; banType = ""; reason = ""; until = 0 }
  };

  public shared(msg) func setPlayerProfile(name : Text, avatarUrl : Text, bio : Text) : async Result.Result<Text, Text> {
    assert (not isBannedNow(msg.caller)); // banned: only withdrawals, claims and listing allowed
    if (Principal.isAnonymous(msg.caller)) return #err("Must be authenticated");
    hydrateRuntimeStateIfNeeded();
    let now = Time.now();
    let createdAt = switch (getPlayerProfileOpt(msg.caller)) { case (?existing) existing.createdAt; case null now };
    let profile : PlayerProfile = { name = name; avatarUrl = avatarUrl; bio = bio; createdAt = createdAt; lastSeen = now };
    playerProfiles.put(msg.caller, profile);
    #ok("Profile saved");
  };

  // The profile picture's NFT details (canister, token, image...) as JSON, so every device shows the same PFP.
  stable var avatarNftEntries : [(Principal, Text)] = [];
  public shared(msg) func setMyAvatarNft(json : Text) : async Result.Result<Text, Text> {
    assert (not isBannedNow(msg.caller)); // banned: only withdrawals, claims and listing allowed
    if (Principal.isAnonymous(msg.caller)) return #err("Must be authenticated");
    if (Text.size(json) > 4_000) return #err("Avatar NFT details too large");
    let rest = Array.filter<(Principal, Text)>(avatarNftEntries, func(e) { not Principal.equal(e.0, msg.caller) });
    avatarNftEntries := if (json == "") { rest } else { Array.append<(Principal, Text)>(rest, [(msg.caller, json)]) };
    #ok("Avatar NFT saved")
  };
  public shared query(msg) func getMyAvatarNft() : async ?Text {
    for ((k, v) in avatarNftEntries.vals()) { if (Principal.equal(k, msg.caller)) return ?v };
    null
  };

  func getPlayerProfileOpt(player : Principal) : ?PlayerProfile {
    if (runtimeStateHydrated) {
      playerProfiles.get(player);
    } else {
      var found : ?PlayerProfile = null;
      for ((p, prof) in playerProfileEntries.vals()) {
        if (Principal.equal(p, player)) { found := ?prof };
      };
      found;
    };
  };

  public query func getPlayerProfile(player : Principal) : async ?PlayerProfile {
    getPlayerProfileOpt(player);
  };

  // Every unique principal holding at least one VP/contributor Gamer Badge — the Player Portal
  // directory only ever shows these players, never every signed-up user. Now a direct read of
  // the badge index's key set instead of a fresh scan of every badge ever created.
  func vpHolderPrincipals() : [Principal] {
    ensureBadgeIndexBuilt();
    Iter.toArray(badgesByOwner.keys());
  };

  func lowerChar(c : Char) : Char {
    let n = Char.toNat32(c);
    if (n >= 65 and n <= 90) { Char.fromNat32(n + 32) } else { c };
  };
  func lowerText(t : Text) : Text { Text.map(t, lowerChar) };

  func toDirectoryPlayer(p : Principal) : DirectoryPlayer {
    switch (getPlayerProfileOpt(p)) {
      case (?pr) { { principal = p; name = pr.name; bio = pr.bio; avatarUrl = pr.avatarUrl; lastSeen = pr.lastSeen } };
      case null { { principal = p; name = ""; bio = ""; avatarUrl = ""; lastSeen = 0 } };
    };
  };

  // Alphabetized by name (case-insensitive) — every directory/search read shares this.
  func sortedVpHolderDirectory() : [DirectoryPlayer] {
    let players = Array.map<Principal, DirectoryPlayer>(vpHolderPrincipals(), toDirectoryPlayer);
    Array.sort<DirectoryPlayer>(players, func(a : DirectoryPlayer, b : DirectoryPlayer) : { #less; #equal; #greater } {
      Text.compare(lowerText(a.name), lowerText(b.name));
    });
  };

  /// Paginated, alphabetized directory of every VP/contributor-badge holder. Only players with
  /// real Voting Power appear here at all — this is not a full signed-up-user list.
  public query func getPlayerDirectory(offset : Nat, limit : Nat) : async { players : [DirectoryPlayer]; total : Nat } {
    let all = sortedVpHolderDirectory();
    let total = all.size();
    if (offset >= total) return { players = []; total = total };
    let endIdx = if (offset + limit > total) total else offset + limit;
    { players = Array.tabulate<DirectoryPlayer>(endIdx - offset, func(i : Nat) : DirectoryPlayer { all[offset + i] }); total = total };
  };

  /// Case-insensitive substring search over the same VP-holder-only, alphabetized directory.
  public query func searchPlayers(q : Text) : async [DirectoryPlayer] {
    let lowerQ = lowerText(q);
    Array.filter<DirectoryPlayer>(sortedVpHolderDirectory(), func(p : DirectoryPlayer) : Bool {
      Text.contains(lowerText(p.name), #text lowerQ);
    });
  };

  // ============================================
  // === GAME SUBMISSIONS ===
  // ============================================

  /// Submit a game to the Backroom (10 ICP fee)
  /// Real The Back submission with a genuine 10 ICP charge — was previously entirely broken on
  /// both paths: the frontend's Token-path call to submitGame() didn't match that function's real
  /// 7-parameter signature (a Candid decode mismatch), and this ICP-path function was declared in
  /// the IDL but never implemented at all (same "frontend wired, backend missing" shape as
  /// Blackhole before tonight's build). Charges from the caller's deposit subaccount straight into
  /// the dedicated Back Treasury subaccount, same pattern as Blackhole's fee.
  /// paysTickets/gameCategory/tokenCost/scoringMode/purchasePrice are accepted for frontend
  /// call-signature compatibility but not persisted, matching the existing adminAddGame precedent
  /// — the stable GameSubmission type has no fields for them today.
  /// The Back is zip-upload-only now (no weblink option) — url starts empty and is filled in by
  /// adminPublishZipGame once admin has reviewed and manually hosted the submitted zip. Status
  /// starts at "backroom-zip-pending" rather than "live" so an unhosted game never appears in the
  /// public Back listing.
  public shared(msg) func submitGameWithPayment(
    name : Text,
    developer : Text,
    thumbnailUrl : Text,
    description : Text,
    compatibility : Text
  ) : async Result.Result<Text, Text> {
    assert (not isBannedNow(msg.caller)); // banned: only withdrawals, claims and listing allowed
    let caller = msg.caller;
    if (Principal.isAnonymous(caller)) return #err("Must be authenticated");
    hydrateRuntimeStateIfNeeded();
    if (Text.size(name) == 0) return #err("Name required");
    if (hasPendingGameSubmission(caller)) return #err("You already have a submission pending admin review. Please wait for it to be approved or rejected before submitting another.");
    if (gameSubmissionInFlight.get(caller) == ?true) {
      return #err("A submission is already being processed. Please wait a moment and try again.");
    };
    gameSubmissionInFlight.put(caller, true);

    let ledgerFeeE8s = 10_000;
    let fromSub = principalToSubaccount(caller);
    let selfPrincipal = Principal.fromActor(ArcadeBackend);
    let bal = await ICP_LEDGER_ICRC1.icrc1_balance_of({ owner = selfPrincipal; subaccount = ?fromSub });
    if (bal < BACK_SUBMISSION_FEE_E8S + ledgerFeeE8s) {
      gameSubmissionInFlight.delete(caller);
      return #err(
        "Not enough ICP in your arcade deposit. The Back submission costs 10 ICP. Available " #
        Nat.toText(bal) # " e8s; need " # Nat.toText(BACK_SUBMISSION_FEE_E8S + ledgerFeeE8s) # " e8s including ledger fee."
      );
    };

    try {
      let transferResult = await ICP_LEDGER.icrc1_transfer({
        to = { owner = selfPrincipal; subaccount = ?BACK_TREASURY_SUBACCOUNT };
        fee = null;
        memo = null;
        from_subaccount = ?fromSub;
        created_at_time = ?ledgerNow();
        amount = BACK_SUBMISSION_FEE_E8S;
      });
      gameSubmissionInFlight.delete(caller);
      switch (transferResult) {
        case (#Ok(blockIndex)) {
          if (Option.isSome(claimedSet.get(blockIndex))) {
            return #err("Duplicate ICP ledger transfer: block " # Nat.toText(blockIndex));
          };
          claimedSet.put(blockIndex, true);
          let id = genGameId();
          let game : GameSubmission = {
            id = id;
            name = name;
            developer = developer;
            url = "";
            thumbnailUrl = thumbnailUrl;
            description = description;
            compatibility = compatibility;
            creator = caller;
            gameTier = "backroom";
            status = "backroom-zip-pending";
            feePaid = BACK_SUBMISSION_FEE_E8S;
            showroomFeePaid = 0;
            txId = blockIndex;
            createdAt = Time.now();
          };
          gameSubmissions.put(id, game);
          logRevenue("game-backroom", BACK_SUBMISSION_FEE_E8S, caller, 4);
          #ok(id)
        };
        case (#Err(e)) { #err(icpTransferErrorText("The Back submission fee", e)) };
      }
    } catch (e) {
      gameSubmissionInFlight.delete(caller);
      #err("The Back submission fee transfer error: " # Error.message(e))
    }
  };

  /// Admin-only withdrawal from the dedicated Back Treasury subaccount.
  public shared(msg) func adminWithdrawBackTreasury(destination : Account, amountE8s : Nat) : async Result.Result<Nat, Text> {
    assert (not isBannedNow(msg.caller)); // banned: only withdrawals, claims and listing allowed
    if (not isAdmin(msg.caller)) return #err("Admin only");
    if (backTreasuryWithdrawalInFlight) return #err("Back Treasury withdrawal already in progress");
    if (amountE8s <= ICP_LEDGER_FEE_E8S) {
      return #err("Back Treasury withdrawal amount must exceed ledger fee dust: " # Nat.toText(ICP_LEDGER_FEE_E8S) # " e8s");
    };
    let selfPrincipal = Principal.fromActor(ArcadeBackend);
    let requiredE8s = amountE8s + ICP_LEDGER_FEE_E8S;
    backTreasuryWithdrawalInFlight := true;
    try {
      let backBalanceE8s = await ICP_LEDGER_ICRC1.icrc1_balance_of({ owner = selfPrincipal; subaccount = ?BACK_TREASURY_SUBACCOUNT });
      if (backBalanceE8s < requiredE8s) {
        backTreasuryWithdrawalInFlight := false;
        return #err(
          "Back Treasury has insufficient funds: " # Nat.toText(backBalanceE8s) #
          " e8s available; need " # Nat.toText(requiredE8s) # " e8s including fee"
        );
      };
      let result = await ICP_LEDGER.icrc1_transfer({
        to = destination;
        fee = null;
        memo = null;
        from_subaccount = ?BACK_TREASURY_SUBACCOUNT;
        created_at_time = ?ledgerNow();
        amount = amountE8s;
      });
      backTreasuryWithdrawalInFlight := false;
      switch (result) {
        case (#Ok(blockIndex)) { #ok(blockIndex) };
        case (#Err(e)) { #err(icpTransferErrorText("Back Treasury withdrawal", e)) };
      }
    } catch (e) {
      backTreasuryWithdrawalInFlight := false;
      #err("Back Treasury withdrawal transfer error: " # Error.message(e))
    }
  };

  /// Read-only: current live balance of the dedicated Back Treasury subaccount (admin only).
  public shared(msg) func getBackTreasuryBalance() : async Result.Result<Nat, Text> {
    assert (not isBannedNow(msg.caller)); // banned: only withdrawals, claims and listing allowed
    if (not isAdmin(msg.caller)) return #err("Admin only");
    let selfPrincipal = Principal.fromActor(ArcadeBackend);
    let balanceE8s = await ICP_LEDGER_ICRC1.icrc1_balance_of({ owner = selfPrincipal; subaccount = ?BACK_TREASURY_SUBACCOUNT });
    #ok(balanceE8s)
  };

  // ============================================
  // === GAME BOOSTS (session #3) ===
  // Creator-paid Spotlight boost: price (admin-adjustable) paid from the buyer's own arcade deposit
  // subaccount into a dedicated Boost Treasury subaccount, so the buyer pays the ledger fee.
  // 7 days per purchase, stacking onto any remaining time. Showroom (incl. DAO Favourites) live games only.
  // Stored as plain stable arrays (not rebuilt runtime maps), so boosts can never read as empty after an upgrade.
  // ============================================
  transient let BOOST_TREASURY_SUBACCOUNT : Blob = Blob.fromArray([
    14, 98, 111, 111, 115, 116, 45, 116,
    114, 101, 97, 115, 117, 114, 121, 0,
    0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0,
  ]);
  transient let BOOST_DURATION_NS : Int = 7 * 24 * 60 * 60 * 1_000_000_000;
  transient let MAX_SPOTLIGHT_SLOTS : Nat = 10; // max games boosted at once (session #3)
  stable var boostPriceE8s : Nat = 200_000_000;
  stable var gameBoostEntries : [(Text, Int)] = [];
  transient var boostPurchaseInFlight = HashMap.HashMap<Principal, Bool>(8, Principal.equal, Principal.hash);
  transient var boostTreasuryWithdrawalInFlight : Bool = false;

  public query func getBoostPrice() : async Nat { boostPriceE8s };

  public query func getSpotlightSlots() : async { used : Nat; max : Nat } {
    let now = Time.now();
    var used = 0;
    for ((_, exp) in gameBoostEntries.vals()) { if (exp > now) used += 1 };
    { used = used; max = MAX_SPOTLIGHT_SLOTS }
  };

  public shared(msg) func adminSetBoostPrice(priceE8s : Nat) : async Result.Result<Nat, Text> {
    assert (not isBannedNow(msg.caller)); // banned: only withdrawals, claims and listing allowed
    if (not isAdmin(msg.caller)) return #err("Admin only");
    if (priceE8s <= ICP_LEDGER_FEE_E8S) return #err("Boost price must exceed the ledger fee");
    boostPriceE8s := priceE8s;
    #ok(boostPriceE8s)
  };

  public query func getActiveBoosts() : async [{ gameId : Text; expiresAt : Int }] {
    let now = Time.now();
    let active = Array.filter<(Text, Int)>(gameBoostEntries, func((_, exp)) { exp > now });
    Array.map<(Text, Int), { gameId : Text; expiresAt : Int }>(active, func((id, exp)) { { gameId = id; expiresAt = exp } })
  };

  public shared(msg) func buyGameBoost(gameId : Text) : async Result.Result<Int, Text> {
    assert (not isBannedNow(msg.caller)); // banned: only withdrawals, claims and listing allowed
    let caller = msg.caller;
    if (Principal.isAnonymous(caller)) return #err("Must be authenticated");
    hydrateRuntimeStateIfNeeded();
    let game = switch (gameSubmissions.get(gameId)) {
      case null return #err("Game not found");
      case (?g) g;
    };
    if (not Principal.equal(game.creator, caller) and not isAdmin(caller)) return #err("Only the game's creator can boost it");
    if (game.gameTier != "showroom" and game.gameTier != "jays-picks") return #err("Only Showroom games can be boosted");
    if (game.status != "live") return #err("Only live games can be boosted");
    // Spotlight cap: checked before any await (atomic), counting in-flight purchases as taken slots so
    // simultaneous buyers can't overshoot. Extending an already-active boost never takes a new slot.
    let nowCheck = Time.now();
    var activeCount = 0;
    var alreadyActive = false;
    for ((id, exp) in gameBoostEntries.vals()) { if (exp > nowCheck) { activeCount += 1; if (id == gameId) alreadyActive := true } };
    if (not alreadyActive and activeCount + boostPurchaseInFlight.size() >= MAX_SPOTLIGHT_SLOTS) {
      return #err("Spotlight is full (" # Nat.toText(MAX_SPOTLIGHT_SLOTS) # " games). Try again when a slot opens up.");
    };
    if (boostPurchaseInFlight.get(caller) != null) return #err("A boost purchase is already in progress");
    boostPurchaseInFlight.put(caller, true);
    let price = boostPriceE8s;
    let fromSub = principalToSubaccount(caller);
    let selfPrincipal = Principal.fromActor(ArcadeBackend);
    try {
      let bal = await ICP_LEDGER_ICRC1.icrc1_balance_of({ owner = selfPrincipal; subaccount = ?fromSub });
      if (bal < price + ICP_LEDGER_FEE_E8S) {
        boostPurchaseInFlight.delete(caller);
        return #err("Not enough ICP in your arcade wallet. Boost costs " # Nat.toText(price) # " e8s plus the " # Nat.toText(ICP_LEDGER_FEE_E8S) # " e8s ledger fee; available " # Nat.toText(bal) # " e8s.");
      };
      let result = await ICP_LEDGER.icrc1_transfer({
        to = { owner = selfPrincipal; subaccount = ?BOOST_TREASURY_SUBACCOUNT };
        fee = ?ICP_LEDGER_FEE_E8S;
        memo = null;
        from_subaccount = ?fromSub;
        created_at_time = ?ledgerNow();
        amount = price;
      });
      boostPurchaseInFlight.delete(caller);
      switch (result) {
        case (#Ok(_blockIndex)) {
          let now = Time.now();
          var current : Int = 0;
          for ((id, exp) in gameBoostEntries.vals()) { if (id == gameId) current := exp };
          let base = if (current > now) current else now;
          let newExp = base + BOOST_DURATION_NS;
          let kept = Array.filter<(Text, Int)>(gameBoostEntries, func((id, exp)) { id != gameId and exp > now });
          gameBoostEntries := Array.append<(Text, Int)>(kept, [(gameId, newExp)]);
          logRevenue("game-boost", price, caller, 8);
          #ok(newExp)
        };
        case (#Err(e)) { #err(icpTransferErrorText("Boost payment", e)) };
      }
    } catch (e) {
      boostPurchaseInFlight.delete(caller);
      #err("Boost payment transfer error: " # Error.message(e))
    }
  };

  /// Admin: free Spotlight boost - identical rules to buyGameBoost (live Showroom games only, 7 days stacking,
  /// counts toward the Spotlight slot cap) minus the payment. No await, so the check-and-write is atomic.
  public shared(msg) func adminBoostGame(gameId : Text) : async Result.Result<Int, Text> {
    assert (not isBannedNow(msg.caller)); // banned: only withdrawals, claims and listing allowed
    if (not isAdmin(msg.caller)) return #err("Admin only");
    hydrateRuntimeStateIfNeeded();
    let game = switch (gameSubmissions.get(gameId)) {
      case null return #err("Game not found");
      case (?g) g;
    };
    if (game.gameTier != "showroom" and game.gameTier != "jays-picks") return #err("Only Showroom games can be boosted");
    if (game.status != "live") return #err("Only live games can be boosted");
    let now = Time.now();
    var activeCount = 0;
    var current : Int = 0;
    for ((id, exp) in gameBoostEntries.vals()) {
      if (exp > now) { activeCount += 1; if (id == gameId) current := exp };
    };
    let alreadyActive = current > now;
    if (not alreadyActive and activeCount + boostPurchaseInFlight.size() >= MAX_SPOTLIGHT_SLOTS) {
      return #err("Spotlight is full (" # Nat.toText(MAX_SPOTLIGHT_SLOTS) # " games). Try again when a slot opens up.");
    };
    let base = if (alreadyActive) current else now;
    let newExp = base + BOOST_DURATION_NS;
    let kept = Array.filter<(Text, Int)>(gameBoostEntries, func((id, exp)) { id != gameId and exp > now });
    gameBoostEntries := Array.append<(Text, Int)>(kept, [(gameId, newExp)]);
    #ok(newExp)
  };

  // ============================================
  // === PRIZE BOOTH NFT SPOTLIGHT (admin-only, session #3) ===
  // Admin curates which NFT listings appear in the Prize Booth Spotlight row. Matches the frontend's
  // existing IDL (getNftSpotlightIds / adminAddNftSpotlight / adminRemoveNftSpotlight), which had no
  // backend until now. Plain stable list: no expiry, no cap - an NFT stays until admin removes it.
  // ============================================
  stable var nftSpotlightIds : [Text] = [];

  transient let MAX_NFT_SPOTLIGHT_SLOTS : Nat = 20;

  // Only listings that are still live count/show - a redeemed, sold, removed or delisted NFT drops out
  // of the Spotlight automatically, whichever path ended it.
  func isLiveNftListing(listingId : Text) : Bool {
    switch (nftListings.get(listingId)) {
      case null false;
      case (?l) l.status == "live";
    }
  };

  public query func getNftSpotlightIds() : async [Text] {
    Array.filter<Text>(nftSpotlightIds, func(id) { isLiveNftListing(id) })
  };

  public shared(msg) func adminAddNftSpotlight(listingId : Text) : async Result.Result<Text, Text> {
    assert (not isBannedNow(msg.caller)); // banned: only withdrawals, claims and listing allowed
    if (not isAdmin(msg.caller)) return #err("Admin only");
    hydrateRuntimeStateIfNeeded();
    if (not isLiveNftListing(listingId)) return #err("Only live NFT listings can be spotlighted");
    // Prune stale entries (redeemed/removed) before counting, so they never hold a slot.
    nftSpotlightIds := Array.filter<Text>(nftSpotlightIds, func(id) { isLiveNftListing(id) });
    for (id in nftSpotlightIds.vals()) { if (id == listingId) return #err("Already in Spotlight") };
    if (nftSpotlightIds.size() >= MAX_NFT_SPOTLIGHT_SLOTS) {
      return #err("NFT Spotlight is full (" # Nat.toText(MAX_NFT_SPOTLIGHT_SLOTS) # " NFTs). Remove one first.");
    };
    nftSpotlightIds := Array.append<Text>(nftSpotlightIds, [listingId]);
    #ok("Added to Spotlight")
  };

  public shared(msg) func adminRemoveNftSpotlight(listingId : Text) : async Result.Result<Text, Text> {
    assert (not isBannedNow(msg.caller)); // banned: only withdrawals, claims and listing allowed
    if (not isAdmin(msg.caller)) return #err("Admin only");
    let before = nftSpotlightIds.size();
    nftSpotlightIds := Array.filter<Text>(nftSpotlightIds, func(id) { id != listingId });
    if (nftSpotlightIds.size() == before) return #err("Not in Spotlight");
    #ok("Removed from Spotlight")
  };

  // === PRIZE BOOTH GRAILS (admin-only flag, session #3) ===
  // Same as the NFT Spotlight minus the cap: a flag, never a collection rename. Live-only, so a
  // redeemed/removed NFT drops out automatically; stays until admin removes it.
  stable var nftGrailIds : [Text] = [];

  public query func getNftGrailIds() : async [Text] {
    Array.filter<Text>(nftGrailIds, func(id) { isLiveNftListing(id) })
  };

  public shared(msg) func adminAddNftGrail(listingId : Text) : async Result.Result<Text, Text> {
    assert (not isBannedNow(msg.caller)); // banned: only withdrawals, claims and listing allowed
    if (not isAdmin(msg.caller)) return #err("Admin only");
    hydrateRuntimeStateIfNeeded();
    if (not isLiveNftListing(listingId)) return #err("Only live NFT listings can be Grails");
    nftGrailIds := Array.filter<Text>(nftGrailIds, func(id) { isLiveNftListing(id) });
    for (id in nftGrailIds.vals()) { if (id == listingId) return #err("Already a Grail") };
    nftGrailIds := Array.append<Text>(nftGrailIds, [listingId]);
    #ok("Marked as Grail")
  };

  public shared(msg) func adminRemoveNftGrail(listingId : Text) : async Result.Result<Text, Text> {
    assert (not isBannedNow(msg.caller)); // banned: only withdrawals, claims and listing allowed
    if (not isAdmin(msg.caller)) return #err("Admin only");
    let before = nftGrailIds.size();
    nftGrailIds := Array.filter<Text>(nftGrailIds, func(id) { id != listingId });
    if (nftGrailIds.size() == before) return #err("Not a Grail");
    #ok("Removed from Grails")
  };

  // ============================================
  // === DAO FAVOURITES (session #3) ===
  // A category flag, never a tier change. Favourites = admin-crowned live games (any tier) plus the
  // top 15 live Back games by DAO-member votes (voters with voting power > 0): score = likes - dislikes,
  // needs >= 1 DAO like and score > 0. Crowned games don't use auto slots. Computed live on every query.
  // ============================================
  type DaoFavourite = { gameId : Text; crowned : Bool; score : Nat };
  stable var daoFavouriteGameIds : [Text] = [];
  transient let DAO_FAV_BACK_TOP_N : Nat = 15;

  func isDaoCrowned(gameId : Text) : Bool {
    for (id in daoFavouriteGameIds.vals()) { if (id == gameId) return true };
    false
  };
  // Games admin removed from DAO Favourites (incl. auto Back picks) - never auto-picked again until re-added.
  stable var daoFavExcludedIds : [Text] = [];
  transient let DAO_FAV_PROPOSAL_CAP : Nat = 10; // community proposals can crown while fewer than 10 are crowned
  func isDaoFavExcluded(gameId : Text) : Bool {
    for (id in daoFavExcludedIds.vals()) { if (id == gameId) return true };
    false
  };
  func crownedLiveCount() : Nat {
    var n : Nat = 0;
    for (id in daoFavouriteGameIds.vals()) {
      switch (gameSubmissions.get(id)) { case (?g) { if (g.status == "live") { n += 1 } }; case null {} };
    };
    n
  };

  public query func getDaoFavourites() : async [DaoFavourite] {
    let out = Buffer.Buffer<DaoFavourite>(32);
    for (id in daoFavouriteGameIds.vals()) {
      switch (gameSubmissions.get(id)) {
        case (?g) { if (g.status == "live") out.add({ gameId = id; crowned = true; score = 0 }) };
        case null {};
      };
    };
    let memberCache = HashMap.HashMap<Principal, Bool>(16, Principal.equal, Principal.hash);
    let tally = HashMap.HashMap<Text, (Nat, Nat)>(16, Text.equal, Text.hash);
    for (v in gameVoteEntries.vals()) {
      let isLiveBack = switch (gameSubmissions.get(v.gameId)) {
        case (?g) { g.status == "live" and g.gameTier == "backroom" };
        case null { false };
      };
      if (isLiveBack) {
        let isMember = switch (memberCache.get(v.voter)) {
          case (?b) { b };
          case null { let b = votingPowerOf(v.voter) > 0; memberCache.put(v.voter, b); b };
        };
        if (isMember) {
          let (l, d) = switch (tally.get(v.gameId)) { case (?t) { t }; case null { (0, 0) } };
          tally.put(v.gameId, if (v.isLike) (l + 1, d) else (l, d + 1));
        };
      };
    };
    let cands = Buffer.Buffer<(Text, Nat, Nat)>(16); // (gameId, score, likes)
    for ((id, (l, d)) in tally.entries()) {
      if (l >= 1 and l > d and not isDaoCrowned(id) and not isDaoFavExcluded(id)) cands.add((id, l - d, l));
    };
    let taken = HashMap.HashMap<Text, Bool>(16, Text.equal, Text.hash);
    var picked = 0;
    let crownedShown = out.size(); // crowned games take their slots first; auto Back picks fill the rest of the 15
    label pickLoop while (crownedShown + picked < DAO_FAV_BACK_TOP_N) {
      var best : ?(Text, Nat, Nat) = null;
      for (c in cands.vals()) {
        if (taken.get(c.0) == null) {
          switch (best) {
            case null { best := ?c };
            case (?b) {
              if (c.1 > b.1 or (c.1 == b.1 and (c.2 > b.2 or (c.2 == b.2 and c.0 < b.0)))) best := ?c;
            };
          };
        };
      };
      switch (best) {
        case null { break pickLoop };
        case (?b) { taken.put(b.0, true); out.add({ gameId = b.0; crowned = false; score = b.1 }); picked += 1 };
      };
    };
    Buffer.toArray(out)
  };

  public shared(msg) func adminSetDaoFavourite(gameId : Text, on : Bool) : async Result.Result<Text, Text> {
    assert (not isBannedNow(msg.caller)); // banned: only withdrawals, claims and listing allowed
    if (not isAdmin(msg.caller)) return #err("Admin only");
    hydrateRuntimeStateIfNeeded();
    if (on) {
      switch (gameSubmissions.get(gameId)) {
        case null { return #err("Game not found") };
        case (?g) { if (g.status != "live") return #err("Only live games can be DAO Favourites") };
      };
      if (isDaoCrowned(gameId)) return #err("Already a DAO Favourite");
      if (crownedLiveCount() >= DAO_FAV_BACK_TOP_N) return #err("DAO Favourites are full (15). Remove one first");
      daoFavExcludedIds := Array.filter<Text>(daoFavExcludedIds, func(x) { x != gameId });
      daoFavouriteGameIds := Array.append<Text>(daoFavouriteGameIds, [gameId]);
      #ok("Added to DAO Favourites")
    } else {
      let before = daoFavouriteGameIds.size();
      daoFavouriteGameIds := Array.filter<Text>(daoFavouriteGameIds, func(id) { id != gameId });
      if (daoFavouriteGameIds.size() == before) {
        if (isDaoFavExcluded(gameId)) return #err("Already removed from DAO Favourites");
        daoFavExcludedIds := Array.append<Text>(daoFavExcludedIds, [gameId]);
        return #ok("Removed from DAO Favourites (it won't return automatically until you add it back)");
      };
      #ok("Removed from DAO Favourites")
    }
  };

  // === JACKPOT NOTIFICATIONS (session #3) ===
  // Built on the existing ticketJackpotWins records: each player has a "last seen" time; wins newer than
  // it are announced once via claimJackpotNotifications, which then advances it. Returns
  // ("ticket:<gameId>", bonusTickets, timestamp) per unseen win, matching the frontend's existing IDL.
  stable var jackpotSeenEntries : [(Principal, Int)] = [];

  func jackpotLastSeen(p : Principal) : Int {
    for (e in jackpotSeenEntries.vals()) { if (Principal.equal(e.0, p)) return e.1 };
    0
  };

  public query func hasJackpotNotifications(p : Principal) : async Bool {
    let seen = jackpotLastSeen(p);
    for (w in ticketJackpotWins.vals()) {
      if (Principal.equal(w.player, p) and w.jackpotTickets > 0 and w.timestamp > seen) return true;
    };
    false
  };

  public shared(msg) func claimJackpotNotifications() : async [(Text, Nat, Int)] {
    let caller = msg.caller;
    if (Principal.isAnonymous(caller)) return [];
    hydrateRuntimeStateIfNeeded();
    let seen = jackpotLastSeen(caller);
    let out = Buffer.Buffer<(Text, Nat, Int)>(4);
    var latest : Int = seen;
    for (w in ticketJackpotWins.vals()) {
      if (Principal.equal(w.player, caller) and w.jackpotTickets > 0 and w.timestamp > seen) {
        out.add(("ticket:" # w.gameId, w.jackpotTickets, w.timestamp));
        if (w.timestamp > latest) latest := w.timestamp;
      };
    };
    if (latest > seen) {
      let others = Array.filter<(Principal, Int)>(jackpotSeenEntries, func(e) { not Principal.equal(e.0, caller) });
      jackpotSeenEntries := Array.append<(Principal, Int)>(others, [(caller, latest)]);
    };
    Buffer.toArray(out)
  };

  // === LOCAL MULTIPLAYER (creator-designated, session #3) ===
  // Set from the submission form and the Details editor; decides the Local Multiplayer home row.
  stable var localMultiplayerGameIds : [Text] = [];

  public query func getLocalMultiplayerGameIds() : async [Text] { localMultiplayerGameIds };

  public shared(msg) func setGameLocalMultiplayer(gameId : Text, on : Bool) : async Result.Result<(), Text> {
    assert (not isBannedNow(msg.caller)); // banned: only withdrawals, claims and listing allowed
    let caller = msg.caller;
    if (Principal.isAnonymous(caller)) return #err("Must be authenticated");
    hydrateRuntimeStateIfNeeded();
    let game = switch (gameSubmissions.get(gameId)) {
      case null return #err("Game not found");
      case (?g) g;
    };
    if (not Principal.equal(game.creator, caller) and not isAdmin(caller)) return #err("Not authorized");
    let without = Array.filter<Text>(localMultiplayerGameIds, func(id) { id != gameId });
    localMultiplayerGameIds := if (on) Array.append<Text>(without, [gameId]) else without;
    #ok(())
  };

  // === SHOWROOM HOPEFULS (Back games, set at submission, session #3) ===
  // Creator can set it only before the game is live (i.e. at submission); admin can change it anytime.
  stable var showroomHopefulGameIds : [Text] = [];

  public query func getShowroomHopefulGameIds() : async [Text] { showroomHopefulGameIds };

  public shared(msg) func setGameShowroomHopeful(gameId : Text, on : Bool) : async Result.Result<(), Text> {
    assert (not isBannedNow(msg.caller)); // banned: only withdrawals, claims and listing allowed
    let caller = msg.caller;
    if (Principal.isAnonymous(caller)) return #err("Must be authenticated");
    hydrateRuntimeStateIfNeeded();
    let game = switch (gameSubmissions.get(gameId)) {
      case null return #err("Game not found");
      case (?g) g;
    };
    if (game.gameTier != "backroom") return #err("Showroom Hopeful is only for The Back games");
    let callerIsAdmin = isAdmin(caller);
    if (not Principal.equal(game.creator, caller) and not callerIsAdmin) return #err("Not authorized");
    if (not callerIsAdmin and game.status == "live") return #err("Showroom Hopeful can only be set at submission");
    let without = Array.filter<Text>(showroomHopefulGameIds, func(id) { id != gameId });
    showroomHopefulGameIds := if (on) Array.append<Text>(without, [gameId]) else without;
    #ok(())
  };

  public shared(msg) func getBoostTreasuryBalance() : async Result.Result<Nat, Text> {
    assert (not isBannedNow(msg.caller)); // banned: only withdrawals, claims and listing allowed
    if (not isAdmin(msg.caller)) return #err("Admin only");
    let selfPrincipal = Principal.fromActor(ArcadeBackend);
    let balanceE8s = await ICP_LEDGER_ICRC1.icrc1_balance_of({ owner = selfPrincipal; subaccount = ?BOOST_TREASURY_SUBACCOUNT });
    #ok(balanceE8s)
  };

  public shared(msg) func adminWithdrawBoostTreasury(destination : Account, amountE8s : Nat) : async Result.Result<Nat, Text> {
    assert (not isBannedNow(msg.caller)); // banned: only withdrawals, claims and listing allowed
    if (not isAdmin(msg.caller)) return #err("Admin only");
    if (boostTreasuryWithdrawalInFlight) return #err("Boost Treasury withdrawal already in progress");
    if (amountE8s <= ICP_LEDGER_FEE_E8S) {
      return #err("Boost Treasury withdrawal amount must exceed ledger fee dust: " # Nat.toText(ICP_LEDGER_FEE_E8S) # " e8s");
    };
    let selfPrincipal = Principal.fromActor(ArcadeBackend);
    let requiredE8s = amountE8s + ICP_LEDGER_FEE_E8S;
    boostTreasuryWithdrawalInFlight := true;
    try {
      let boostBalanceE8s = await ICP_LEDGER_ICRC1.icrc1_balance_of({ owner = selfPrincipal; subaccount = ?BOOST_TREASURY_SUBACCOUNT });
      if (boostBalanceE8s < requiredE8s) {
        boostTreasuryWithdrawalInFlight := false;
        return #err("Boost Treasury has insufficient funds: " # Nat.toText(boostBalanceE8s) # " e8s available; need " # Nat.toText(requiredE8s) # " e8s including fee");
      };
      let result = await ICP_LEDGER.icrc1_transfer({
        to = destination;
        fee = ?ICP_LEDGER_FEE_E8S;
        memo = null;
        from_subaccount = ?BOOST_TREASURY_SUBACCOUNT;
        created_at_time = ?ledgerNow();
        amount = amountE8s;
      });
      boostTreasuryWithdrawalInFlight := false;
      switch (result) {
        case (#Ok(blockIndex)) { #ok(blockIndex) };
        case (#Err(e)) { #err(icpTransferErrorText("Boost Treasury withdrawal", e)) };
      }
    } catch (e) {
      boostTreasuryWithdrawalInFlight := false;
      #err("Boost Treasury withdrawal transfer error: " # Error.message(e))
    }
  };

  // ============================================
  // === CHARITABLE TICKET FUNDING (session #3) ===
  // Creator (or admin) donates ICP to back extra tickets in their live Showroom Ticket game's pool at the
  // published 1 ICP = 1,000 tickets. ICP moves from the donor's arcade deposit subaccount into general
  // custody (the same backing as play-funded tickets); the donor pays the ledger fee. The amount is
  // rounded down to whole tickets BEFORE paying, so the donor is only charged for tickets they get.
  // ============================================
  transient let TICKET_FUND_MIN_E8S : Nat = 10_000_000; // 0.1 ICP
  transient let E8S_PER_TICKET : Nat = 100_000;         // 1 ICP = 1,000 tickets
  transient var ticketFundInFlight = HashMap.HashMap<Principal, Bool>(8, Principal.equal, Principal.hash);

  public shared(msg) func fundGameTickets(gameId : Text, amountE8s : Nat) : async Result.Result<Nat, Text> {
    assert (not isBannedNow(msg.caller)); // banned: only withdrawals, claims and listing allowed
    let caller = msg.caller;
    if (Principal.isAnonymous(caller)) return #err("Must be authenticated");
    hydrateRuntimeStateIfNeeded();
    let game = switch (gameSubmissions.get(gameId)) {
      case null return #err("Game not found");
      case (?g) g;
    };
    if (not Principal.equal(game.creator, caller) and not isAdmin(caller)) return #err("Only the game's creator can fund its tickets");
    if (game.gameTier != "showroom" and game.gameTier != "jays-picks") return #err("Only Showroom Ticket games can be funded");
    if (not isTicketGameSubmission(game)) return #err("Only Ticket games have a ticket pool to fund");
    if (game.status != "live") return #err("Only live games can be funded");
    if (amountE8s < TICKET_FUND_MIN_E8S) return #err("Minimum ticket funding is 0.1 ICP");
    let ticketCount = amountE8s / E8S_PER_TICKET;
    let usedE8s = ticketCount * E8S_PER_TICKET;
    if (ticketFundInFlight.get(caller) != null) return #err("A ticket funding is already in progress");
    ticketFundInFlight.put(caller, true);
    let fromSub = principalToSubaccount(caller);
    let selfPrincipal = Principal.fromActor(ArcadeBackend);
    try {
      let bal = await ICP_LEDGER_ICRC1.icrc1_balance_of({ owner = selfPrincipal; subaccount = ?fromSub });
      if (bal < usedE8s + ICP_LEDGER_FEE_E8S) {
        ticketFundInFlight.delete(caller);
        return #err("Not enough ICP in your arcade wallet. Funding " # Nat.toText(ticketCount) # " tickets costs " # Nat.toText(usedE8s) # " e8s plus the " # Nat.toText(ICP_LEDGER_FEE_E8S) # " e8s ledger fee; available " # Nat.toText(bal) # " e8s.");
      };
      let result = await ICP_LEDGER.icrc1_transfer({
        to = { owner = selfPrincipal; subaccount = null };
        fee = ?ICP_LEDGER_FEE_E8S;
        memo = null;
        from_subaccount = ?fromSub;
        created_at_time = ?ledgerNow();
        amount = usedE8s;
      });
      ticketFundInFlight.delete(caller);
      switch (result) {
        case (#Ok(_blockIndex)) {
          addToGameRawTicketPool(gameId, ticketCount);
          addToGameBackedTicketPool(gameId, ticketCount);
          clampBackedPoolToRaw(gameId);
          #ok(ticketCount)
        };
        case (#Err(e)) { #err(icpTransferErrorText("Ticket funding payment", e)) };
      }
    } catch (e) {
      ticketFundInFlight.delete(caller);
      #err("Ticket funding transfer error: " # Error.message(e))
    }
  };

  // ============================================
  // === SHOWROOM TICKET-POOL SEED (session #3) ===
  // When a Showroom Ticket game goes live, 20% of the Showroom fee its creator actually paid (recorded in
  // showroomFeePaid) moves from the Showroom Treasury into general custody and backs that many tickets
  // (1 ICP = 1,000) in the game's pool. The transfer's ledger fee was prepaid by the submitter at
  // submission time. At most once per game: marked seeded before the await, unmarked if the transfer fails.
  // ============================================
  transient let TICKET_POOL_SEED_PERCENT : Nat = 20;
  stable var seededTicketPoolGames : [Text] = [];

  func seedTicketPoolIfEligible(gameId : Text) : async Result.Result<Nat, Text> {
    hydrateRuntimeStateIfNeeded();
    let game = switch (gameSubmissions.get(gameId)) {
      case null return #err("Game not found");
      case (?g) g;
    };
    if (game.gameTier != "showroom" and game.gameTier != "jays-picks") return #ok(0);
    if (not isTicketGameSubmission(game)) return #ok(0);
    if (game.showroomFeePaid == 0) return #ok(0);
    for (id in seededTicketPoolGames.vals()) { if (id == gameId) return #ok(0) };
    let seedE8s = (game.showroomFeePaid * TICKET_POOL_SEED_PERCENT) / 100;
    let ticketCount = seedE8s / E8S_PER_TICKET;
    let usedE8s = ticketCount * E8S_PER_TICKET;
    if (ticketCount == 0) return #ok(0);
    seededTicketPoolGames := Array.append<Text>(seededTicketPoolGames, [gameId]);
    let selfPrincipal = Principal.fromActor(ArcadeBackend);
    try {
      let result = await ICP_LEDGER.icrc1_transfer({
        to = { owner = selfPrincipal; subaccount = null };
        fee = ?ICP_LEDGER_FEE_E8S;
        memo = null;
        from_subaccount = ?SHOWROOM_TREASURY_SUBACCOUNT;
        created_at_time = ?ledgerNow();
        amount = usedE8s;
      });
      switch (result) {
        case (#Ok(_)) {
          addToGameRawTicketPool(gameId, ticketCount);
          addToGameBackedTicketPool(gameId, ticketCount);
          clampBackedPoolToRaw(gameId);
          #ok(ticketCount)
        };
        case (#Err(e)) {
          seededTicketPoolGames := Array.filter<Text>(seededTicketPoolGames, func(id) { id != gameId });
          #err(icpTransferErrorText("Ticket pool seed", e))
        };
      }
    } catch (e) {
      seededTicketPoolGames := Array.filter<Text>(seededTicketPoolGames, func(id) { id != gameId });
      #err("Ticket pool seed transfer error: " # Error.message(e))
    }
  };

  /// Admin: seed (or retry seeding) a live Showroom Ticket game's pool - also backfills games published before seeding existed.
  public shared(msg) func adminSeedTicketPool(gameId : Text) : async Result.Result<Nat, Text> {
    assert (not isBannedNow(msg.caller)); // banned: only withdrawals, claims and listing allowed
    if (not isAdmin(msg.caller)) return #err("Admin only");
    hydrateRuntimeStateIfNeeded();
    switch (gameSubmissions.get(gameId)) {
      case null { return #err("Game not found") };
      case (?g) { if (g.status != "live") return #err("Game is not live") };
    };
    switch (await seedTicketPoolIfEligible(gameId)) {
      case (#ok(0)) { #err("Not eligible (not a paid Showroom Ticket game) or already seeded") };
      case (#ok(n)) { #ok(n) };
      case (#err(e)) { #err(e) };
    }
  };

  /// Real implementation — was previously declared in the frontend IDL and called by
  /// refreshBackSubmissionFeeDisplay, but never existed on the backend, so the call always
  /// silently failed and the UI fell back to stale hardcoded fee text.
  /// Both tiers are now ICP-only (zip-upload submissions) — backSubmitFeeTokens is kept in the
  /// return shape at 0 for frontend call-signature compatibility with any caller still expecting
  /// the field, rather than risking a decode break; it is no longer a real, chargeable option.
  public query func getSubmissionFeeConfig() : async { backSubmitFeeTokens : Nat; backSubmitFeeIcpE8s : Nat; showroomSubmitFeeIcpE8s : Nat } {
    { backSubmitFeeTokens = 0; backSubmitFeeIcpE8s = BACK_SUBMISSION_FEE_E8S; showroomSubmitFeeIcpE8s = SHOWROOM_SUBMISSION_FEE_E8S }
  };

  /// Real Showroom submission, replacing the old Token-based path which called submitGame(...)
  /// with a 12-argument call that never matched that function's real 7-parameter signature (the
  /// same Candid mismatch found and fixed for The Back). Showroom is now zip-upload-only too — url
  /// starts empty. Status starts at "showroom-zip-pending" (waiting for admin to host the zip);
  /// once admin hosts it via Upload Game to Chain and clicks Accept, adminPublishZipGame makes it
  /// live directly (one-step publish, session #3 - no separate content-review stage).
  public shared(msg) func submitShowroomGameWithPayment(
    name : Text,
    developer : Text,
    thumbnailUrl : Text,
    description : Text,
    compatibility : Text
  ) : async Result.Result<Text, Text> {
    assert (not isBannedNow(msg.caller)); // banned: only withdrawals, claims and listing allowed
    let caller = msg.caller;
    if (Principal.isAnonymous(caller)) return #err("Must be authenticated");
    hydrateRuntimeStateIfNeeded();
    if (Text.size(name) == 0) return #err("Name required");
    if (hasPendingGameSubmission(caller)) return #err("You already have a submission pending admin review. Please wait for it to be approved or rejected before submitting another.");
    if (gameSubmissionInFlight.get(caller) == ?true) {
      return #err("A submission is already being processed. Please wait a moment and try again.");
    };
    gameSubmissionInFlight.put(caller, true);

    let ledgerFeeE8s = 10_000;
    let fromSub = principalToSubaccount(caller);
    let selfPrincipal = Principal.fromActor(ArcadeBackend);
    let bal = await ICP_LEDGER_ICRC1.icrc1_balance_of({ owner = selfPrincipal; subaccount = ?fromSub });
    if (bal < SHOWROOM_SUBMISSION_FEE_E8S + ICP_LEDGER_FEE_E8S + ledgerFeeE8s) {
      gameSubmissionInFlight.delete(caller);
      return #err(
        "Not enough ICP in your arcade deposit. Showroom submission costs 25 ICP. Available " #
        Nat.toText(bal) # " e8s; need " # Nat.toText(SHOWROOM_SUBMISSION_FEE_E8S + ICP_LEDGER_FEE_E8S + ledgerFeeE8s) # " e8s including ledger fees."
      );
    };

    try {
      let transferResult = await ICP_LEDGER.icrc1_transfer({
        to = { owner = selfPrincipal; subaccount = ?SHOWROOM_TREASURY_SUBACCOUNT };
        fee = null;
        memo = null;
        from_subaccount = ?fromSub;
        created_at_time = ?ledgerNow();
        amount = SHOWROOM_SUBMISSION_FEE_E8S + ICP_LEDGER_FEE_E8S; // + submitter-prepaid fee for the later ticket-pool seed transfer
      });
      gameSubmissionInFlight.delete(caller);
      switch (transferResult) {
        case (#Ok(blockIndex)) {
          if (Option.isSome(claimedSet.get(blockIndex))) {
            return #err("Duplicate ICP ledger transfer: block " # Nat.toText(blockIndex));
          };
          claimedSet.put(blockIndex, true);
          let id = genGameId();
          let game : GameSubmission = {
            id = id;
            name = name;
            developer = developer;
            url = "";
            thumbnailUrl = thumbnailUrl;
            description = description;
            compatibility = compatibility;
            creator = caller;
            gameTier = "showroom";
            status = "showroom-zip-pending";
            feePaid = 0;
            showroomFeePaid = SHOWROOM_SUBMISSION_FEE_E8S;
            txId = blockIndex;
            createdAt = Time.now();
          };
          gameSubmissions.put(id, game);
          logRevenue("game-showroom", SHOWROOM_SUBMISSION_FEE_E8S, caller, 5);
          #ok(id)
        };
        case (#Err(e)) { #err(icpTransferErrorText("Showroom submission fee", e)) };
      }
    } catch (e) {
      gameSubmissionInFlight.delete(caller);
      #err("Showroom submission fee transfer error: " # Error.message(e))
    }
  };

  /// Admin-only withdrawal from the dedicated Showroom Treasury subaccount.
  public shared(msg) func adminWithdrawShowroomTreasury(destination : Account, amountE8s : Nat) : async Result.Result<Nat, Text> {
    assert (not isBannedNow(msg.caller)); // banned: only withdrawals, claims and listing allowed
    if (not isAdmin(msg.caller)) return #err("Admin only");
    if (showroomTreasuryWithdrawalInFlight) return #err("Showroom Treasury withdrawal already in progress");
    if (amountE8s <= ICP_LEDGER_FEE_E8S) {
      return #err("Showroom Treasury withdrawal amount must exceed ledger fee dust: " # Nat.toText(ICP_LEDGER_FEE_E8S) # " e8s");
    };
    let selfPrincipal = Principal.fromActor(ArcadeBackend);
    let requiredE8s = amountE8s + ICP_LEDGER_FEE_E8S;
    showroomTreasuryWithdrawalInFlight := true;
    try {
      let showroomBalanceE8s = await ICP_LEDGER_ICRC1.icrc1_balance_of({ owner = selfPrincipal; subaccount = ?SHOWROOM_TREASURY_SUBACCOUNT });
      if (showroomBalanceE8s < requiredE8s) {
        showroomTreasuryWithdrawalInFlight := false;
        return #err(
          "Showroom Treasury has insufficient funds: " # Nat.toText(showroomBalanceE8s) #
          " e8s available; need " # Nat.toText(requiredE8s) # " e8s including fee"
        );
      };
      let result = await ICP_LEDGER.icrc1_transfer({
        to = destination;
        fee = null;
        memo = null;
        from_subaccount = ?SHOWROOM_TREASURY_SUBACCOUNT;
        created_at_time = ?ledgerNow();
        amount = amountE8s;
      });
      showroomTreasuryWithdrawalInFlight := false;
      switch (result) {
        case (#Ok(blockIndex)) { #ok(blockIndex) };
        case (#Err(e)) { #err(icpTransferErrorText("Showroom Treasury withdrawal", e)) };
      }
    } catch (e) {
      showroomTreasuryWithdrawalInFlight := false;
      #err("Showroom Treasury withdrawal transfer error: " # Error.message(e))
    }
  };

  /// Read-only: current live balance of the dedicated Showroom Treasury subaccount (admin only).
  public shared(msg) func getShowroomTreasuryBalance() : async Result.Result<Nat, Text> {
    assert (not isBannedNow(msg.caller)); // banned: only withdrawals, claims and listing allowed
    if (not isAdmin(msg.caller)) return #err("Admin only");
    let selfPrincipal = Principal.fromActor(ArcadeBackend);
    let balanceE8s = await ICP_LEDGER_ICRC1.icrc1_balance_of({ owner = selfPrincipal; subaccount = ?SHOWROOM_TREASURY_SUBACCOUNT });
    #ok(balanceE8s)
  };

  // ============================================
  // === REVENUE SPLIT ACCUMULATORS (new arcade-share + DAO pool) ===
  // Per-play/purchase revenue splits credit these plain internal Nat counters rather than moving
  // ICP to a dedicated subaccount, since the underlying ICP is already sitting in the canister's
  // own general custody the moment a deposit becomes Tokens (Jay's explicit design: "no reason to
  // reroute anything"). Withdraw functions below transfer with from_subaccount=null, exactly
  // matching claimRoyalties' proven pattern - debit the counter before the ledger await (Motoko
  // only re-enters at await points, so this alone prevents double-claim), then a real icrc1_transfer,
  // restoring the counter on failure. Each play/purchase type gets its own separate arcade-share
  // accumulator per Jay's explicit request, rather than one shared "arcade" balance. The DAO pool is
  // a single unified accumulator across all three types (not split per-type) and deliberately has NO
  // withdraw function at all anywhere in this file - Jay was explicit that no one, including admin,
  // should ever be able to withdraw from it. It stays inert until the future DAO lottery system
  // mints real Tokens from it (see dao-treasury-build memory notes for the full design).
  // Retired names, kept ONLY so upgrades stay memory-compatible (enhanced orthogonal persistence
  // refuses to drop stable vars). Never read or written. Remove before mainnet (fresh install).
  stable var showroomArcadeShareE8s : Nat = 0;
  stable var backArcadeShareE8s : Nat = 0;
  stable var backPurchaseArcadeShareE8s : Nat = 0;
  stable var showroomTicketArcadeShareE8s : Nat = 0;
  stable var showroomNonTicketArcadeShareE8s : Nat = 0;
  stable var showroomPurchaseArcadeShareE8s : Nat = 0;
  stable var daoTreasuryE8s : Nat = 0;
  // Prize Booth arcade share: player-listed NFT sales (1.5%), Official NFT redemptions (80%), VP badge sales (80%).
  stable var prizeBoothArcadeShareE8s : Nat = 0;
  // Lifetime DAO income by source (tracking starts at this upgrade) + lottery payout totals.
  stable var daoInGamesE8s : Nat = 0;
  stable var daoInProposalsE8s : Nat = 0;
  stable var daoInOfficialNftE8s : Nat = 0;
  stable var daoInPlayerNftE8s : Nat = 0;
  stable var daoInVpBadgeE8s : Nat = 0;
  stable var lotteryTokensPaidTotal : Nat = 0;
  stable var lotteryTicketsPaidTotal : Nat = 0;
  stable var lotteryDrawsTotal : Nat = 0;

  public query func getShowroomTicketArcadeShareBalance() : async Nat { showroomTicketArcadeShareE8s };
  public query func getShowroomNonTicketArcadeShareBalance() : async Nat { showroomNonTicketArcadeShareE8s };
  public query func getShowroomPurchaseArcadeShareBalance() : async Nat { showroomPurchaseArcadeShareE8s };
  public query func getDaoTreasuryBalance() : async Nat { daoTreasuryE8s };
  public query func getPrizeBoothArcadeShareBalance() : async Nat { prizeBoothArcadeShareE8s };

  // === DAO LOTTERY SETTINGS (stage 1; the draw engine comes in stage 2) ===
  stable var lotteryEnabled : Bool = false;
  stable var tokenLotteryPayoutBps : Nat = 1000; // 10.00% of the DAO treasury reserved per token cycle
  stable var ticketLotteryPayoutBps : Nat = 900; // 9.00% of the DAO treasury reserved per ticket cycle
  stable var lotteryTestHoursPerWeek : Nat = 0; // 0 = normal speed; N = one lottery "week" lasts N hours (local testing)

  public shared(msg) func adminSetLotteryEnabled(on : Bool) : async Result.Result<Text, Text> {
    assert (not isBannedNow(msg.caller)); // banned: only withdrawals, claims and listing allowed
    if (not isAdmin(msg.caller)) return #err("Admin only");
    lotteryEnabled := on;
    #ok(if (on) "Lottery ON: new cycles start when affordable" else "Lottery PAUSED: running cycles still finish, no new cycles start")
  };

  public shared(msg) func adminSetLotteryPayoutBps(kind : Text, bps : Nat) : async Result.Result<Text, Text> {
    assert (not isBannedNow(msg.caller)); // banned: only withdrawals, claims and listing allowed
    if (not isAdmin(msg.caller)) return #err("Admin only");
    if (bps < 100 or bps > 5000) return #err("Payout must be between 1.00% and 50.00% (100-5000 basis points)");
    if (kind == "token") { tokenLotteryPayoutBps := bps; return #ok("Token lottery payout set; applies from the next cycle") };
    if (kind == "ticket") { ticketLotteryPayoutBps := bps; return #ok("Ticket lottery payout set; applies from the next cycle") };
    #err("Kind must be token or ticket")
  };

  public shared(msg) func adminSetLotteryTestSpeed(hoursPerWeek : Nat) : async Result.Result<Text, Text> {
    assert (not isBannedNow(msg.caller)); // banned: only withdrawals, claims and listing allowed
    if (not isAdmin(msg.caller)) return #err("Admin only");
    if (hoursPerWeek > 168) return #err("Use 0 for normal speed, or 1-168 hours per lottery week");
    lotteryTestHoursPerWeek := hoursPerWeek;
    #ok(if (hoursPerWeek == 0) "Lottery at normal speed" else "Lottery test speed: 1 week = " # Nat.toText(hoursPerWeek) # " hour(s)")
  };

  public query func getLotterySettings() : async { enabled : Bool; tokenPayoutBps : Nat; ticketPayoutBps : Nat; testHoursPerWeek : Nat } {
    { enabled = lotteryEnabled; tokenPayoutBps = tokenLotteryPayoutBps; ticketPayoutBps = ticketLotteryPayoutBps; testHoursPerWeek = lotteryTestHoursPerWeek }
  };

  // === DAO LOTTERY ENGINE (stage 2) ===
  // Token lottery: 8-week cycles, 4 draws (every 2 weeks); entries at 3/6/9 VP Badges (max 3).
  // Ticket lottery: 8-week cycles, 2 draws (every 4 weeks); entries at 4/8 VP Badges (max 2).
  // Entries are snapshotted at cycle start; each entry wins exactly once per cycle, all wins equal.
  // The cycle's prize reserve is locked out of the DAO treasury at the start, sized so every entry
  // gets exactly perWin. Switching the lottery off only stops NEW cycles; running cycles finish.
  type LotteryCycle = {
    kind : Text;
    startedAt : Int;
    drawIntervalNs : Int;
    drawsTotal : Nat;
    drawsDone : Nat;
    nextDrawAt : Int;
    perWin : Nat;
    entriesTotal : Nat;
    remaining : [(Principal, Nat)];
  };
  type LotteryWin = { player : Principal; kind : Text; tier : Nat; amount : Nat; timestamp : Int; cycleStart : Int };
  type LotteryCycleView = { startedAt : Int; drawsTotal : Nat; drawsDone : Nat; nextDrawAt : Int; perWin : Nat; entriesTotal : Nat; remaining : Nat };

  stable var tokenLotteryCycle : ?LotteryCycle = null;
  stable var ticketLotteryCycle : ?LotteryCycle = null;
  stable var lotteryWins : [LotteryWin] = [];
  stable var lotteryHistoryEntries : [(Int, Text, [Text], Nat)] = [];
  stable var lotterySeenEntries : [(Principal, Int)] = [];
  transient var lotteryTickRunning : Bool = false;
  transient var lotteryTickStartedAt : Int = 0;

  func lotteryCycleOf(kind : Text) : ?LotteryCycle { if (kind == "token") { tokenLotteryCycle } else { ticketLotteryCycle } };
  func setLotteryCycle(kind : Text, c : ?LotteryCycle) { if (kind == "token") { tokenLotteryCycle := c } else { ticketLotteryCycle := c } };

  func lotteryWeekNs() : Int {
    if (lotteryTestHoursPerWeek == 0) { 604_800_000_000_000 } else { lotteryTestHoursPerWeek * 3_600_000_000_000 }
  };

  func lotterySnapshot(kind : Text) : [(Principal, Nat)] {
    let thresholds : [Nat] = if (kind == "token") { [3, 6, 9] } else { [4, 8] };
    let perkId = if (kind == "token") { "token-lottery" } else { "ticket-lottery" };
    // Candidates: VP badge holders plus Official NFT holders (lottery abilities work without badges).
    let seen = HashMap.HashMap<Principal, Bool>(64, Principal.equal, Principal.hash);
    let people = Buffer.Buffer<Principal>(64);
    for (p in vpHolderPrincipals().vals()) { if (seen.get(p) == null) { seen.put(p, true); people.add(p) } };
    for ((_, o) in officialNftOwnerEntries.vals()) { if (seen.get(o) == null) { seen.put(o, true); people.add(o) } };
    let buf = Buffer.Buffer<(Principal, Nat)>(16);
    for (p in people.vals()) {
      if (not isAdmin(p) and not isBannedNow(p)) {
        let n = vpBadgeCountOf(p);
        var tier : Nat = 0;
        for (t in thresholds.vals()) {
          tier += 1;
          if (n >= t) { buf.add((p, tier)) };
        };
        var extra = abilityCountOf(p, perkId); // +1 entry per lottery ability (stacking)
        while (extra > 0) { tier += 1; buf.add((p, tier)); extra -= 1 };
      };
    };
    Buffer.toArray(buf)
  };

  func tryStartLotteryCycle(kind : Text) : Bool {
    if (not lotteryEnabled) return false;
    switch (lotteryCycleOf(kind)) { case (?_) { return false }; case null {} };
    let entries = lotterySnapshot(kind);
    let e = entries.size();
    if (e == 0) return false;
    let bps = if (kind == "token") { tokenLotteryPayoutBps } else { ticketLotteryPayoutBps };
    let unit = if (kind == "token") { TOKEN_LIABILITY_E8S } else { TICKET_LIABILITY_E8S };
    let perWin = (daoTreasuryE8s * bps / 10_000) / (e * unit);
    if (perWin == 0) return false;
    daoTreasuryE8s -= perWin * e * unit;
    let week = lotteryWeekNs();
    let now = Time.now();
    let interval : Int = if (kind == "token") { 2 * week } else { 4 * week };
    setLotteryCycle(kind, ?{
      kind = kind;
      startedAt = now;
      drawIntervalNs = interval;
      drawsTotal = if (kind == "token") { 4 } else { 2 };
      drawsDone = 0;
      nextDrawAt = now + interval;
      perWin = perWin;
      entriesTotal = e;
      remaining = entries;
    });
    true
  };

  func runLotteryDraw(kind : Text, seed : Blob, salt : Nat64) {
    switch (lotteryCycleOf(kind)) {
      case null {};
      case (?c) {
        let rem = c.remaining.size();
        let drawsLeft : Nat = if (c.drawsTotal > c.drawsDone) { c.drawsTotal - c.drawsDone } else { 1 };
        let k : Nat = if (drawsLeft <= 1) { rem } else { (rem + drawsLeft - 1) / drawsLeft };
        let arr = Array.thaw<(Principal, Nat)>(c.remaining);
        var st : Nat64 = 0x9E3779B97F4A7C15 ^ salt;
        for (b in Blob.toArray(seed).vals()) {
          st := (st ^ Nat64.fromNat(Nat8.toNat(b))) *% 6364136223846793005 +% 1442695040888963407;
        };
        if (st == 0) { st := 1 };
        var i : Nat = 0;
        while (i < k) {
          st ^= st << 13;
          st ^= st >> 7;
          st ^= st << 17;
          let j = i + Nat64.toNat(st) % (rem - i);
          let tmp = arr[i];
          arr[i] := arr[j];
          arr[j] := tmp;
          i += 1;
        };
        let now = Time.now();
        let winnersText = Buffer.Buffer<Text>(k);
        let wins = Buffer.fromArray<LotteryWin>(lotteryWins);
        var w : Nat = 0;
        while (w < k) {
          let (p, tier) = arr[w];
          if (kind == "token") { tokens.put(p, getTokenBalance(p) + c.perWin) } else { tickets.put(p, getTicketBalance(p) + c.perWin) };
          wins.add({ player = p; kind = kind; tier = tier; amount = c.perWin; timestamp = now; cycleStart = c.startedAt });
          winnersText.add(Principal.toText(p));
          w += 1;
        };
        lotteryWins := Buffer.toArray(wins);
        if (k > 0) {
          lotteryDrawsTotal += 1;
          if (kind == "token") { lotteryTokensPaidTotal += c.perWin * k } else { lotteryTicketsPaidTotal += c.perWin * k };
          lotteryHistoryEntries := Array.append<(Int, Text, [Text], Nat)>(lotteryHistoryEntries, [(now, if (kind == "token") { "token-lottery" } else { "ticket-lottery" }, Buffer.toArray(winnersText), c.perWin * k)]);
        };
        let rest = Buffer.Buffer<(Principal, Nat)>(rem);
        var r : Nat = k;
        while (r < rem) { rest.add(arr[r]); r += 1 };
        let done = c.drawsDone + 1;
        if (done >= c.drawsTotal or rest.size() == 0) {
          setLotteryCycle(kind, null);
        } else {
          setLotteryCycle(kind, ?{ c with drawsDone = done; nextDrawAt = c.nextDrawAt + c.drawIntervalNs; remaining = Buffer.toArray(rest) });
        };
      };
    };
  };

  func lotteryTick() : async () {
    let now = Time.now();
    // Self-healing lock: a check older than 5 minutes is treated as stuck and ignored.
    if (lotteryTickRunning and now - lotteryTickStartedAt < 300_000_000_000) return;
    lotteryTickRunning := true;
    lotteryTickStartedAt := now;
    hydrateRuntimeStateIfNeeded();
    // Cheap path: lottery off and no cycle in progress -> only settle DAO binding proposals
    // (which this timer also drives); skip the random-seed await and all lottery cycle work.
    if (not lotteryEnabled and tokenLotteryCycle == null and ticketLotteryCycle == null) {
      processBindingProposals();
      lotteryTickRunning := false;
      return;
    };
    var due = false;
    for (kind in ["token", "ticket"].vals()) {
      switch (lotteryCycleOf(kind)) { case (?c) { if (now >= c.nextDrawAt) { due := true } }; case null {} };
    };
    if (due) {
      let seed : ?Blob = try { ?(await Random.blob()) } catch (_) { null };
      switch (seed) {
        case (?sd) {
          hydrateRuntimeStateIfNeeded();
          let now2 = Time.now();
          switch (tokenLotteryCycle) { case (?c) { if (now2 >= c.nextDrawAt) { runLotteryDraw("token", sd, 1) } }; case null {} };
          switch (ticketLotteryCycle) { case (?c) { if (now2 >= c.nextDrawAt) { runLotteryDraw("ticket", sd, 2) } }; case null {} };
        };
        case null {};
      };
    };
    processBindingProposals();
    ignore tryStartLotteryCycle("token");
    ignore tryStartLotteryCycle("ticket");
    lotteryTickRunning := false;
  };

  public shared(msg) func adminRunLottery() : async Result.Result<Text, Text> {
    assert (not isBannedNow(msg.caller)); // banned: only withdrawals, claims and listing allowed
    if (not isAdmin(msg.caller)) return #err("Admin only");
    await lotteryTick();
    #ok("Lottery check complete: due draws run, new cycles started if on and affordable")
  };

  // TESTING ONLY (remove before mainnet): make the current cycle's next draw due now, then run a check.
  public shared(msg) func adminLotteryDrawNow(kind : Text) : async Result.Result<Text, Text> {
    assert (not isBannedNow(msg.caller)); // banned: only withdrawals, claims and listing allowed
    if (not isAdmin(msg.caller)) return #err("Admin only");
    switch (lotteryCycleOf(kind)) {
      case null { return #err("No running " # kind # " lottery cycle") };
      case (?c) { setLotteryCycle(kind, ?{ c with nextDrawAt = Time.now() }) };
    };
    await lotteryTick();
    #ok("Draw forced for the " # kind # " lottery")
  };

  func lotteryCycleView(c : ?LotteryCycle) : ?LotteryCycleView {
    switch (c) {
      case null { null };
      case (?x) { ?{ startedAt = x.startedAt; drawsTotal = x.drawsTotal; drawsDone = x.drawsDone; nextDrawAt = x.nextDrawAt; perWin = x.perWin; entriesTotal = x.entriesTotal; remaining = x.remaining.size() } };
    }
  };

  public query func getLotteryStatus() : async { enabled : Bool; daoTreasuryE8s : Nat; token : ?LotteryCycleView; ticket : ?LotteryCycleView } {
    { enabled = lotteryEnabled; daoTreasuryE8s = daoTreasuryE8s; token = lotteryCycleView(tokenLotteryCycle); ticket = lotteryCycleView(ticketLotteryCycle) }
  };

  public query func getLotteryHistory() : async [(Int, Text, [Text], Nat)] { lotteryHistoryEntries };

  // Admin solvency report: everything the arcade owes (valued in ICP) vs the real ICP ledger
  // balance of the canister's main account - the account deposits land in and claims pay from.
  // Dedicated treasury subaccounts and users' own deposit subaccounts are separate and excluded.
  public shared(msg) func adminGetSolvencyReport() : async Result.Result<{
    tokensE8s : Nat; ticketsE8s : Nat; gameTicketPoolsE8s : Nat;
    creatorRoyaltiesE8s : Nat; nftSellerEarningsE8s : Nat; tipEarningsE8s : Nat; refundsE8s : Nat;
    arcadeSharesE8s : Nat; daoTreasuryE8s : Nat; lotteryLockedE8s : Nat;
    totalLiabilitiesE8s : Nat; ledgerBalanceE8s : Nat; surplusE8s : Nat; shortfallE8s : Nat;
  }, Text> {
    assert (not isBannedNow(msg.caller)); // banned: only withdrawals, claims and listing allowed
    if (not isAdmin(msg.caller)) return #err("Admin only");
    hydrateRuntimeStateIfNeeded();
    var tok : Nat = 0; for (v in tokens.vals()) { tok += v };
    var tix : Nat = 0; for (v in tickets.vals()) { tix += v };
    var pools : Nat = 0; for (v in gameBackedTicketPools.vals()) { pools += v };
    var roy : Nat = 0; for (v in royalties.vals()) { roy += v };
    var sel : Nat = 0; for (v in nftSellerEarningsE8s.vals()) { sel += v };
    var tipSum : Nat = 0; for (v in tipEarnings.vals()) { tipSum += v };
    var refundSum : Nat = 0; for (v in refundsE8s.vals()) { refundSum += v };
    let arcade = showroomTicketArcadeShareE8s + showroomNonTicketArcadeShareE8s + showroomPurchaseArcadeShareE8s + prizeBoothArcadeShareE8s;
    let lockedTok : Nat = switch (tokenLotteryCycle) { case null { 0 }; case (?c) { c.perWin * c.remaining.size() * TOKEN_LIABILITY_E8S } };
    let lockedTix : Nat = switch (ticketLotteryCycle) { case null { 0 }; case (?c) { c.perWin * c.remaining.size() * TICKET_LIABILITY_E8S } };
    let tokensE8s = tok * TOKEN_LIABILITY_E8S;
    let ticketsE8s = tix * TICKET_LIABILITY_E8S;
    let poolsE8s = pools * TICKET_LIABILITY_E8S;
    let total = tokensE8s + ticketsE8s + poolsE8s + roy + sel + tipSum + refundSum + arcade + daoTreasuryE8s + lockedTok + lockedTix;
    let ledger : Nat = try {
      await ICP_LEDGER_ICRC1.icrc1_balance_of({ owner = Principal.fromActor(ArcadeBackend); subaccount = null })
    } catch (e) { return #err("Ledger balance check failed: " # Error.message(e)) };
    #ok({
      tokensE8s = tokensE8s; ticketsE8s = ticketsE8s; gameTicketPoolsE8s = poolsE8s;
      creatorRoyaltiesE8s = roy; nftSellerEarningsE8s = sel; tipEarningsE8s = tipSum; refundsE8s = refundSum;
      arcadeSharesE8s = arcade; daoTreasuryE8s = daoTreasuryE8s; lotteryLockedE8s = lockedTok + lockedTix;
      totalLiabilitiesE8s = total; ledgerBalanceE8s = ledger;
      surplusE8s = if (ledger > total) { ledger - total } else { 0 };
      shortfallE8s = if (total > ledger) { total - ledger } else { 0 };
    })
  };

  public query func getDaoTreasuryOverview() : async {
    balanceE8s : Nat; lockedTokenE8s : Nat; lockedTicketE8s : Nat;
    inGamesE8s : Nat; inProposalsE8s : Nat; inOfficialNftE8s : Nat; inPlayerNftE8s : Nat; inVpBadgeE8s : Nat;
    lotteryTokensPaid : Nat; lotteryTicketsPaid : Nat; lotteryDraws : Nat; vpHolders : Nat;
  } {
    let lockedTok : Nat = switch (tokenLotteryCycle) { case null { 0 }; case (?c) { c.perWin * c.remaining.size() * TOKEN_LIABILITY_E8S } };
    let lockedTix : Nat = switch (ticketLotteryCycle) { case null { 0 }; case (?c) { c.perWin * c.remaining.size() * TICKET_LIABILITY_E8S } };
    var holders : Nat = 0;
    for (p in vpHolderPrincipals().vals()) { if (not isAdmin(p) and vpBadgeCountOf(p) > 0) { holders += 1 } };
    {
      balanceE8s = daoTreasuryE8s; lockedTokenE8s = lockedTok; lockedTicketE8s = lockedTix;
      inGamesE8s = daoInGamesE8s; inProposalsE8s = daoInProposalsE8s; inOfficialNftE8s = daoInOfficialNftE8s;
      inPlayerNftE8s = daoInPlayerNftE8s; inVpBadgeE8s = daoInVpBadgeE8s;
      lotteryTokensPaid = lotteryTokensPaidTotal; lotteryTicketsPaid = lotteryTicketsPaidTotal; lotteryDraws = lotteryDrawsTotal;
      vpHolders = holders;
    }
  };

  public query func getMyLotteryEntries(p : Principal) : async [(Text, Nat, Bool)] {
    let out = Buffer.Buffer<(Text, Nat, Bool)>(5);
    for (kind in ["token", "ticket"].vals()) {
      switch (lotteryCycleOf(kind)) {
        case null {};
        case (?c) {
          for ((q, tier) in c.remaining.vals()) { if (Principal.equal(q, p)) { out.add((kind, tier, false)) } };
          for (w in lotteryWins.vals()) { if (Principal.equal(w.player, p) and w.kind == kind and w.cycleStart == c.startedAt) { out.add((kind, w.tier, true)) } };
        };
      };
    };
    Buffer.toArray(out)
  };

  func lotteryLastSeen(p : Principal) : Int {
    for (e in lotterySeenEntries.vals()) { if (Principal.equal(e.0, p)) return e.1 };
    0
  };

  public query func hasLotteryWins(p : Principal) : async Bool {
    let seen = lotteryLastSeen(p);
    for (w in lotteryWins.vals()) { if (Principal.equal(w.player, p) and w.timestamp > seen) return true };
    false
  };

  public shared(msg) func claimLotteryWinNotifications() : async [(Text, Nat, Nat, Int)] {
    let caller = msg.caller;
    if (Principal.isAnonymous(caller)) return [];
    let seen = lotteryLastSeen(caller);
    let out = Buffer.Buffer<(Text, Nat, Nat, Int)>(4);
    var latest : Int = seen;
    for (w in lotteryWins.vals()) {
      if (Principal.equal(w.player, caller) and w.timestamp > seen) {
        out.add((w.kind, w.tier, w.amount, w.timestamp));
        if (w.timestamp > latest) { latest := w.timestamp };
      };
    };
    if (latest > seen) {
      let others = Array.filter<(Principal, Int)>(lotterySeenEntries, func(e) { not Principal.equal(e.0, caller) });
      lotterySeenEntries := Array.append<(Principal, Int)>(others, [(caller, latest)]);
    };
    Buffer.toArray(out)
  };


  /// Admin-only withdrawal from the Showroom ticket-game arcade-share accumulator (from_subaccount=null: this is
  /// a plain internal counter against the canister's general ICP balance, not a dedicated subaccount).
  public shared(msg) func adminWithdrawShowroomTicketArcadeShare(destination : Account, amountE8s : Nat) : async Result.Result<Nat, Text> {
    assert (not isBannedNow(msg.caller)); // banned: only withdrawals, claims and listing allowed
    if (not isAdmin(msg.caller)) return #err("Admin only");
    // Session #3: this share pays its own ledger fee (debited with the amount), never general custody.
    let totalDebit = amountE8s + ICP_LEDGER_FEE_E8S;
    if (totalDebit > showroomTicketArcadeShareE8s) {
      return #err("Showroom ticket arcade share has insufficient balance: " # Nat.toText(showroomTicketArcadeShareE8s) # " e8s available (needs amount + " # Nat.toText(ICP_LEDGER_FEE_E8S) # " e8s ledger fee)");
    };
    showroomTicketArcadeShareE8s -= totalDebit;
    try {
      let result = await ICP_LEDGER.icrc1_transfer({
        to = destination;
        fee = ?ICP_LEDGER_FEE_E8S;
        memo = null;
        from_subaccount = null;
        created_at_time = ?ledgerNow();
        amount = amountE8s;
      });
      switch (result) {
        case (#Ok(blockIndex)) { #ok(blockIndex) };
        case (#Err(e)) {
          showroomTicketArcadeShareE8s += totalDebit;
          #err(icpTransferErrorText("Showroom ticket arcade share withdrawal", e))
        };
      }
    } catch (e) {
      showroomTicketArcadeShareE8s += totalDebit;
      #err("Showroom ticket arcade share withdrawal transfer error: " # Error.message(e))
    }
  };

  /// Admin-only withdrawal from the Showroom non-ticket per-play arcade-share accumulator.
  public shared(msg) func adminWithdrawShowroomNonTicketArcadeShare(destination : Account, amountE8s : Nat) : async Result.Result<Nat, Text> {
    assert (not isBannedNow(msg.caller)); // banned: only withdrawals, claims and listing allowed
    if (not isAdmin(msg.caller)) return #err("Admin only");
    // Session #3: this share pays its own ledger fee (debited with the amount), never general custody.
    let totalDebit = amountE8s + ICP_LEDGER_FEE_E8S;
    if (totalDebit > showroomNonTicketArcadeShareE8s) {
      return #err("Showroom non-ticket arcade share has insufficient balance: " # Nat.toText(showroomNonTicketArcadeShareE8s) # " e8s available (needs amount + " # Nat.toText(ICP_LEDGER_FEE_E8S) # " e8s ledger fee)");
    };
    showroomNonTicketArcadeShareE8s -= totalDebit;
    try {
      let result = await ICP_LEDGER.icrc1_transfer({
        to = destination;
        fee = ?ICP_LEDGER_FEE_E8S;
        memo = null;
        from_subaccount = null;
        created_at_time = ?ledgerNow();
        amount = amountE8s;
      });
      switch (result) {
        case (#Ok(blockIndex)) { #ok(blockIndex) };
        case (#Err(e)) {
          showroomNonTicketArcadeShareE8s += totalDebit;
          #err(icpTransferErrorText("Showroom non-ticket arcade share withdrawal", e))
        };
      }
    } catch (e) {
      showroomNonTicketArcadeShareE8s += totalDebit;
      #err("Showroom non-ticket arcade share withdrawal transfer error: " # Error.message(e))
    }
  };

  /// Admin-only withdrawal from the Showroom full-game-purchase arcade-share accumulator.
  public shared(msg) func adminWithdrawShowroomPurchaseArcadeShare(destination : Account, amountE8s : Nat) : async Result.Result<Nat, Text> {
    assert (not isBannedNow(msg.caller)); // banned: only withdrawals, claims and listing allowed
    if (not isAdmin(msg.caller)) return #err("Admin only");
    // Session #3: this share pays its own ledger fee (debited with the amount), never general custody.
    let totalDebit = amountE8s + ICP_LEDGER_FEE_E8S;
    if (totalDebit > showroomPurchaseArcadeShareE8s) {
      return #err("Showroom purchase arcade share has insufficient balance: " # Nat.toText(showroomPurchaseArcadeShareE8s) # " e8s available (needs amount + " # Nat.toText(ICP_LEDGER_FEE_E8S) # " e8s ledger fee)");
    };
    showroomPurchaseArcadeShareE8s -= totalDebit;
    try {
      let result = await ICP_LEDGER.icrc1_transfer({
        to = destination;
        fee = ?ICP_LEDGER_FEE_E8S;
        memo = null;
        from_subaccount = null;
        created_at_time = ?ledgerNow();
        amount = amountE8s;
      });
      switch (result) {
        case (#Ok(blockIndex)) { #ok(blockIndex) };
        case (#Err(e)) {
          showroomPurchaseArcadeShareE8s += totalDebit;
          #err(icpTransferErrorText("Showroom purchase arcade share withdrawal", e))
        };
      }
    } catch (e) {
      showroomPurchaseArcadeShareE8s += totalDebit;
      #err("Showroom purchase arcade share withdrawal transfer error: " # Error.message(e))
    }
  };


  /// Admin-only withdrawal from the Prize Booth (NFT + VP badge sales) arcade-share accumulator.
  public shared(msg) func adminWithdrawPrizeBoothArcadeShare(destination : Account, amountE8s : Nat) : async Result.Result<Nat, Text> {
    assert (not isBannedNow(msg.caller)); // banned: only withdrawals, claims and listing allowed
    if (not isAdmin(msg.caller)) return #err("Admin only");
    // Session #3: this share pays its own ledger fee (debited with the amount), never general custody.
    let totalDebit = amountE8s + ICP_LEDGER_FEE_E8S;
    if (totalDebit > prizeBoothArcadeShareE8s) {
      return #err("Prize Booth arcade share has insufficient balance: " # Nat.toText(prizeBoothArcadeShareE8s) # " e8s available (needs amount + " # Nat.toText(ICP_LEDGER_FEE_E8S) # " e8s ledger fee)");
    };
    prizeBoothArcadeShareE8s -= totalDebit;
    try {
      let result = await ICP_LEDGER.icrc1_transfer({
        to = destination;
        fee = ?ICP_LEDGER_FEE_E8S;
        memo = null;
        from_subaccount = null;
        created_at_time = ?ledgerNow();
        amount = amountE8s;
      });
      switch (result) {
        case (#Ok(blockIndex)) { #ok(blockIndex) };
        case (#Err(e)) {
          prizeBoothArcadeShareE8s += totalDebit;
          #err(icpTransferErrorText("Prize Booth arcade share withdrawal", e))
        };
      }
    } catch (e) {
      prizeBoothArcadeShareE8s += totalDebit;
      #err("Prize Booth arcade share withdrawal transfer error: " # Error.message(e))
    }
  };
  // ============================================
  // === GAME ZIP UPLOAD QUEUE (The Back + Showroom) ===
  // Submitters upload their game zip in chunks directly into arcade_backend's own storage, since
  // only the admin identity has write permission on the real game_assets hosting canister.
  // Admin then downloads the reassembled zip from the admin panel, personally reviews its
  // contents, and — only once satisfied — manually hosts it via the existing admin-only "Upload
  // Game to Chain" tool before calling adminPublishZipGame to flip the listing live. Nothing here
  // auto-publishes anything; deliberate by design.
  // ============================================

  /// One pending submission at a time per user, across both tiers — a clearer, easier-to-reason-
  /// about rule than counting raw upload slots (which confused users when a stuck/failed upload
  /// left stale slots occupied). Checked before any fee is charged, so a blocked resubmission
  /// attempt never risks a double-charge.
  // Immediate, pre-await lock closing a real race window in submitGameWithPayment/
  // submitShowroomGameWithPayment below: hasPendingGameSubmission only sees a submission after its
  // ICP transfer has already succeeded, but both functions have their own await points (the balance
  // check, then the transfer itself) before that record is ever written. Motoko only interleaves
  // messages at await points, so two near-simultaneous calls (e.g. an accidental double-click) can
  // both pass hasPendingGameSubmission's check before either has written anything - this closes
  // that gap by locking synchronously, before any await, and clearing it on every exit path.
  transient var gameSubmissionInFlight = HashMap.HashMap<Principal, Bool>(8, Principal.equal, Principal.hash);

  func hasPendingGameSubmission(who : Principal) : Bool {
    for ((_, game) in gameSubmissions.entries()) {
      if (Principal.equal(game.creator, who) and (game.status == "backroom-zip-pending" or game.status == "showroom-zip-pending")) {
        return true;
      };
    };
    false
  };

  func countActivePendingZipUploadsForUser(who : Principal) : Nat {
    var count = 0;
    for ((_, upload) in pendingZipUploads.entries()) {
      if (Principal.equal(upload.submitter, who) and upload.status != "published") {
        count += 1;
      };
    };
    count
  };

  public shared(msg) func startZipUpload(gameId : Text, purpose : Text, filename : Text, totalBytes : Nat, chunkCount : Nat) : async Result.Result<Text, Text> {
    assert (not isBannedNow(msg.caller)); // banned: only withdrawals, claims and listing allowed
    let caller = msg.caller;
    if (Principal.isAnonymous(caller)) return #err("Must be authenticated");
    hydrateRuntimeStateIfNeeded();
    let game = switch (gameSubmissions.get(gameId)) {
      case null return #err("Game not found");
      case (?g) g;
    };
    if (not Principal.equal(game.creator, caller)) return #err("You did not submit this game");
    if (purpose != "zip" and purpose != "thumbnail") return #err("Invalid upload purpose");
    let maxBytes = if (purpose == "thumbnail") MAX_THUMBNAIL_UPLOAD_BYTES else MAX_ZIP_TOTAL_BYTES;
    if (totalBytes == 0 or totalBytes > maxBytes) {
      return #err("File must be between 1 byte and " # Nat.toText(maxBytes / (1024*1024)) # "MB");
    };
    if (chunkCount == 0) return #err("Chunk count must be greater than zero");
    if (countActivePendingZipUploadsForUser(caller) >= MAX_PENDING_ZIP_UPLOADS_PER_USER) {
      return #err("Too many pending uploads. Please wait for admin to review your existing submissions first.");
    };
    zipUploadCounter += 1;
    let uploadId = "zip-" # Nat.toText(zipUploadCounter) # "-" # Int.toText(Time.now());
    let upload : PendingZipUpload = {
      id = uploadId;
      gameId = gameId;
      submitter = caller;
      tier = game.gameTier;
      filename = purpose # "::" # filename;
      totalBytes = totalBytes;
      chunkCount = chunkCount;
      receivedChunks = 0;
      status = "uploading";
      createdAt = Time.now();
    };
    pendingZipUploads.put(uploadId, upload);
    #ok(uploadId)
  };

  public shared(msg) func uploadZipChunk(uploadId : Text, chunkIndex : Nat, data : Blob) : async Result.Result<Nat, Text> {
    assert (not isBannedNow(msg.caller)); // banned: only withdrawals, claims and listing allowed
    let caller = msg.caller;
    if (Principal.isAnonymous(caller)) return #err("Must be authenticated");
    let upload = switch (pendingZipUploads.get(uploadId)) {
      case null return #err("Upload not found");
      case (?u) u;
    };
    if (not Principal.equal(upload.submitter, caller)) return #err("Not your upload");
    if (upload.status != "uploading") return #err("This upload is no longer accepting chunks");
    if (chunkIndex >= upload.chunkCount) return #err("Chunk index out of range");
    if (data.size() > MAX_ZIP_CHUNK_BYTES) {
      return #err("Chunk too large: " # Nat.toText(data.size()) # " bytes; max " # Nat.toText(MAX_ZIP_CHUNK_BYTES) # " bytes per chunk");
    };
    let chunkKey = uploadId # "#" # Nat.toText(chunkIndex);
    let isNewChunk = Option.isNull(zipChunks.get(chunkKey));
    zipChunks.put(chunkKey, data);
    let updated : PendingZipUpload = {
      upload with receivedChunks = if (isNewChunk) upload.receivedChunks + 1 else upload.receivedChunks
    };
    pendingZipUploads.put(uploadId, updated);
    #ok(updated.receivedChunks)
  };

  public shared(msg) func finalizeZipUpload(uploadId : Text) : async Result.Result<Text, Text> {
    assert (not isBannedNow(msg.caller)); // banned: only withdrawals, claims and listing allowed
    let caller = msg.caller;
    if (Principal.isAnonymous(caller)) return #err("Must be authenticated");
    let upload = switch (pendingZipUploads.get(uploadId)) {
      case null return #err("Upload not found");
      case (?u) u;
    };
    if (not Principal.equal(upload.submitter, caller)) return #err("Not your upload");
    if (upload.receivedChunks != upload.chunkCount) {
      return #err("Missing chunks: received " # Nat.toText(upload.receivedChunks) # " of " # Nat.toText(upload.chunkCount));
    };
    let updated : PendingZipUpload = { upload with status = "ready" };
    pendingZipUploads.put(uploadId, updated);
    #ok("Zip received. Pending admin review.")
  };

  public shared(msg) func adminGetPendingZipUploads() : async Result.Result<[PendingZipUpload], Text> {
    assert (not isBannedNow(msg.caller)); // banned: only withdrawals, claims and listing allowed
    if (not isAdmin(msg.caller)) return #err("Admin only");
    hydrateRuntimeStateIfNeeded();
    let out = Buffer.Buffer<PendingZipUpload>(pendingZipUploads.size());
    for ((_, upload) in pendingZipUploads.entries()) {
      out.add(upload);
    };
    #ok(Buffer.toArray(out))
  };

  public shared(msg) func adminGetZipChunk(uploadId : Text, chunkIndex : Nat) : async Result.Result<Blob, Text> {
    assert (not isBannedNow(msg.caller)); // banned: only withdrawals, claims and listing allowed
    if (not isAdmin(msg.caller)) return #err("Admin only");
    switch (zipChunks.get(uploadId # "#" # Nat.toText(chunkIndex))) {
      case null #err("Chunk not found");
      case (?data) #ok(data);
    }
  };

  public shared(msg) func adminMarkZipDownloaded(uploadId : Text) : async Result.Result<Text, Text> {
    assert (not isBannedNow(msg.caller)); // banned: only withdrawals, claims and listing allowed
    if (not isAdmin(msg.caller)) return #err("Admin only");
    switch (pendingZipUploads.get(uploadId)) {
      case null #err("Upload not found");
      case (?upload) {
        pendingZipUploads.put(uploadId, { upload with status = "downloaded" });
        #ok("Marked downloaded")
      };
    }
  };

  func deletePendingZipUploadAndChunks(uploadId : Text, chunkCount : Nat) {
    pendingZipUploads.delete(uploadId);
    var i = 0;
    while (i < chunkCount) {
      zipChunks.delete(uploadId # "#" # Nat.toText(i));
      i += 1;
    };
  };

  /// A submission always queues up to two uploads (zip + thumbnail), but reject/remove used to
  /// only clean up whichever single upload id the caller happened to pass in — leaving the other
  /// one (usually the thumbnail) permanently orphaned in storage. An orphaned upload still counts
  /// toward that user's per-user pending-upload cap forever, and still shows up in the admin
  /// pending-submissions view (which groups by upload record, not by the game's actual status),
  /// making already-rejected/removed games appear to still be awaiting review. This sweeps every
  /// upload actually tied to a game, so reject/remove genuinely leaves nothing behind.
  func deleteAllPendingUploadsForGameId(gameId : Text) {
    let toDelete = Array.filter<(Text, PendingZipUpload)>(Iter.toArray(pendingZipUploads.entries()), func((_, u)) { u.gameId == gameId });
    for ((uploadId, upload) in toDelete.vals()) {
      deletePendingZipUploadAndChunks(uploadId, upload.chunkCount);
    };
  };

  public shared(msg) func adminDeletePendingZipUpload(uploadId : Text) : async Result.Result<Text, Text> {
    assert (not isBannedNow(msg.caller)); // banned: only withdrawals, claims and listing allowed
    if (not isAdmin(msg.caller)) return #err("Admin only");
    switch (pendingZipUploads.get(uploadId)) {
      case null #err("Upload not found");
      case (?upload) {
        deletePendingZipUploadAndChunks(uploadId, upload.chunkCount);
        #ok("Deleted")
      };
    }
  };

  /// Admin: records where Upload Game to Chain actually hosted a pending submission's files,
  /// without changing its status. Lets the folder name differ from the game ID (e.g. "swing-blade")
  /// while the submission's own record - and every per-game setting keyed by its ID (monetization,
  /// category, accessibility, pricing) - stays the one record that goes live on Accept.
  public shared(msg) func adminStageZipGameUrl(gameId : Text, hostedUrl : Text) : async Result.Result<Text, Text> {
    assert (not isBannedNow(msg.caller)); // banned: only withdrawals, claims and listing allowed
    if (not isAdmin(msg.caller)) return #err("Admin only");
    hydrateRuntimeStateIfNeeded();
    let game = switch (gameSubmissions.get(gameId)) {
      case null return #err("Game not found");
      case (?g) g;
    };
    if (game.status != "backroom-zip-pending" and game.status != "showroom-zip-pending") {
      return #err("Not a pending submission: " # game.status);
    };
    if (Text.size(hostedUrl) == 0) return #err("Hosted URL required");
    gameSubmissions.put(gameId, { game with url = hostedUrl });
    #ok("Hosted URL staged")
  };

  /// Admin: after manually hosting a reviewed zip via the existing "Upload Game to Chain" tool,
  /// this sets the game's real url and moves it out of its pending-zip state. Both tiers go
  /// straight to "live" (one-step publish, Jay session #3: Accept is the final approval; the old
  /// "showroom-pending" review stage and approveGameShowroom are no longer reachable from here).
  /// hostedUrl may be empty, in which case the URL staged by adminStageZipGameUrl is used.
  public shared(msg) func adminPublishZipGame(gameId : Text, hostedUrl : Text, uploadId : Text) : async Result.Result<Text, Text> {
    assert (not isBannedNow(msg.caller)); // banned: only withdrawals, claims and listing allowed
    if (not isAdmin(msg.caller)) return #err("Admin only");
    hydrateRuntimeStateIfNeeded();
    let game = switch (gameSubmissions.get(gameId)) {
      case null return #err("Game not found");
      case (?g) g;
    };
    if (game.status != "backroom-zip-pending" and game.status != "showroom-zip-pending") {
      return #err("Not a pending submission: " # game.status);
    };
    // Ticket games need a complete, enabled payout table to go live - otherwise every score pays 0.
    if (isTicketGameSubmission(game)) {
      switch (gamePayoutConfigs.get(gameId)) {
        case null { return #err("Set the payout table before accepting this Ticket game (7 score thresholds) - without one every score pays 0 tickets.") };
        case (?cfg) {
          if (not cfg.enabled or (cfg.thresholds.size() != 7 and cfg.thresholds.size() != 8)) return #err("Enable a complete payout ladder before accepting this Ticket game.");
        };
      };
    };
    let finalUrl = if (Text.size(hostedUrl) > 0) hostedUrl else game.url;
    if (Text.size(finalUrl) == 0) return #err("No hosted files yet - run Upload Game to Chain for this submission first");
    let tierLabel = if (game.gameTier == "showroom") "the Showroom" else "The Back";
    let updated : GameSubmission = { game with url = finalUrl; status = "live" };
    gameSubmissions.put(gameId, updated);
    createNotification(game.creator, "Game Published!", "\"" # game.name # "\" is now live in " # tierLabel # ".", gameId);
    switch (pendingZipUploads.get(uploadId)) {
      case (?upload) { deletePendingZipUploadAndChunks(uploadId, upload.chunkCount) };
      case null {};
    };
    let seedMsg = if (game.gameTier == "showroom" or game.gameTier == "jays-picks") {
      switch (await seedTicketPoolIfEligible(gameId)) {
        case (#ok(0)) { "" };
        case (#ok(n)) { " Ticket pool seeded with " # Nat.toText(n) # " tickets." };
        case (#err(e)) { " Ticket pool seeding failed (" # e # ") - retry with adminSeedTicketPool." };
      }
    } else { "" };
    #ok("Game published." # seedMsg)
  };

  /// Admin: after downloading and reviewing a queued thumbnail and hosting it themselves (via
  /// their own already-trusted identity, same as the existing admin thumbnail-upload path), sets
  /// the game's real thumbnail URL and clears the pending upload.
  public shared(msg) func adminSetGameThumbnail(gameId : Text, thumbnailUrl : Text, uploadId : Text) : async Result.Result<Text, Text> {
    assert (not isBannedNow(msg.caller)); // banned: only withdrawals, claims and listing allowed
    if (not isAdmin(msg.caller)) return #err("Admin only");
    hydrateRuntimeStateIfNeeded();
    let game = switch (gameSubmissions.get(gameId)) {
      case null return #err("Game not found");
      case (?g) g;
    };
    if (Text.size(thumbnailUrl) == 0) return #err("Thumbnail URL required");
    let updated : GameSubmission = { game with thumbnailUrl = thumbnailUrl };
    gameSubmissions.put(gameId, updated);
    switch (pendingZipUploads.get(uploadId)) {
      case (?upload) { deletePendingZipUploadAndChunks(uploadId, upload.chunkCount) };
      case null {};
    };
    #ok("Thumbnail set")
  };

  func createNotification(recipient : Principal, title : Text, message : Text, gameId : Text) {
    notificationCounter += 1;
    let id = "notif-" # Nat.toText(notificationCounter) # "-" # Int.toText(Time.now());
    let n : UserNotification = { id; recipient; title; message; gameId; createdAt = Time.now(); seen = false };
    notifications.put(id, n);
  };

  /// Returns the caller's unseen notifications only — the frontend shows each as a popup then
  /// calls markNotificationSeen so it never repeats.
  public query(msg) func getMyNotifications() : async [UserNotification] {
    let caller = msg.caller;
    if (Principal.isAnonymous(caller)) return [];
    hydrateRuntimeStateIfNeeded();
    let out = Buffer.Buffer<UserNotification>(4);
    for ((_, n) in notifications.entries()) {
      if (Principal.equal(n.recipient, caller) and not n.seen) { out.add(n) };
    };
    Buffer.toArray(out)
  };

  public shared(msg) func markNotificationSeen(id : Text) : async Result.Result<(), Text> {
    let caller = msg.caller;
    switch (notifications.get(id)) {
      case null return #err("Notification not found");
      case (?n) {
        if (not Principal.equal(n.recipient, caller)) return #err("Not your notification");
        notifications.put(id, { n with seen = true });
        #ok(())
      };
    }
  };

  /// Category is settable once by the submitter (as part of their own submission) or any time by
  /// admin (per Jay's "auto-set by user's choice, admin adjustable" spec). Stored separately from
  /// GameSubmission itself — see gameCategoryEntries' comment for why.
  public shared(msg) func setGameCategory(gameId : Text, category : Text) : async Result.Result<(), Text> {
    assert (not isBannedNow(msg.caller)); // banned: only withdrawals, claims and listing allowed
    let caller = msg.caller;
    if (Principal.isAnonymous(caller)) return #err("Must be authenticated");
    hydrateRuntimeStateIfNeeded();
    let game = switch (gameSubmissions.get(gameId)) {
      case null return #err("Game not found");
      case (?g) g;
    };
    if (not Principal.equal(game.creator, caller) and not isAdmin(caller)) return #err("Not authorized");
    gameCategories.put(gameId, category);
    #ok(())
  };

  public query func getGameCategory(gameId : Text) : async Text {
    switch (gameCategories.get(gameId)) { case null ""; case (?c) c };
  };

  /// Creator-facing accessibility/build tags, mirroring setGameCategory's exact auth pattern
  /// (settable once by the submitter, adjustable any time by admin) rather than adminSetGamePricing's
  /// admin-only pattern, since these are meant to be the creator's own honest self-description of
  /// their game, not something admin decides for them.
  public shared(msg) func setGameAccessibility(gameId : Text, keyboardOnly : Bool, keyboardAndMouse : Bool, controllerReady : Bool, madeWithAi : Bool) : async Result.Result<(), Text> {
    assert (not isBannedNow(msg.caller)); // banned: only withdrawals, claims and listing allowed
    let caller = msg.caller;
    if (Principal.isAnonymous(caller)) return #err("Must be authenticated");
    hydrateRuntimeStateIfNeeded();
    let game = switch (gameSubmissions.get(gameId)) {
      case null return #err("Game not found");
      case (?g) g;
    };
    if (not Principal.equal(game.creator, caller) and not isAdmin(caller)) return #err("Not authorized");
    gameAccessibility.put(gameId, (keyboardOnly, keyboardAndMouse, controllerReady, madeWithAi));
    #ok(())
  };

  /// Session #3: creator (or admin) edits their own game's description from the Developer Dashboard.
  public shared(msg) func setGameDescription(gameId : Text, description : Text) : async Result.Result<(), Text> {
    assert (not isBannedNow(msg.caller)); // banned: only withdrawals, claims and listing allowed
    let caller = msg.caller;
    if (Principal.isAnonymous(caller)) return #err("Must be authenticated");
    hydrateRuntimeStateIfNeeded();
    let game = switch (gameSubmissions.get(gameId)) {
      case null return #err("Game not found");
      case (?g) g;
    };
    if (not Principal.equal(game.creator, caller) and not isAdmin(caller)) return #err("Not authorized");
    if (Text.size(description) == 0) return #err("Description cannot be empty");
    if (Text.size(description) > 1000) return #err("Description too long (max 1000 characters)");
    gameSubmissions.put(gameId, { game with description = description });
    #ok(())
  };

  public query func getGameAccessibility(gameId : Text) : async { keyboardOnly : Bool; keyboardAndMouse : Bool; controllerReady : Bool; madeWithAi : Bool } {
    switch (gameAccessibility.get(gameId)) {
      case null { { keyboardOnly = false; keyboardAndMouse = false; controllerReady = false; madeWithAi = false } };
      case (?(ko, kam, cr, ai)) { { keyboardOnly = ko; keyboardAndMouse = kam; controllerReady = cr; madeWithAi = ai } };
    };
  };

  /// Creator-declared monetization intent, same auth pattern as setGameAccessibility (settable by
  /// the submitter, adjustable any time by admin). paysTickets is the real, authoritative source of
  /// ticket-pool eligibility (see isTicketGameSubmission below) - a ticket game can never also be
  /// purchasable, enforced server-side here regardless of what the frontend UI allows.
  /// wantsPurchasable is a request/hint only; admin still sets the real price via
  /// adminSetGamePricing when approving.
  public shared(msg) func setGameMonetization(gameId : Text, paysTickets : Bool, wantsPurchasable : Bool) : async Result.Result<(), Text> {
    assert (not isBannedNow(msg.caller)); // banned: only withdrawals, claims and listing allowed
    let caller = msg.caller;
    if (Principal.isAnonymous(caller)) return #err("Must be authenticated");
    hydrateRuntimeStateIfNeeded();
    let game = switch (gameSubmissions.get(gameId)) {
      case null return #err("Game not found");
      case (?g) g;
    };
    if (not Principal.equal(game.creator, caller) and not isAdmin(caller)) return #err("Not authorized");
    if (paysTickets and wantsPurchasable) return #err("Ticket games cannot be purchasable");
    gameMonetization.put(gameId, (paysTickets, wantsPurchasable));
    #ok(())
  };

  public query func getGameMonetization(gameId : Text) : async { paysTickets : Bool; wantsPurchasable : Bool } {
    switch (gameMonetization.get(gameId)) {
      case null { { paysTickets = false; wantsPurchasable = false } };
      case (?(pt, wp)) { { paysTickets = pt; wantsPurchasable = wp } };
    };
  };

  /// Admin-only pricing setter, per Jay's design: unlike category, pricing is never set by the
  /// submitter, only by admin. 0 = unset in both params, matching adminAddGame's existing
  /// convention. Supports The Back's three models directly: both 0 = free, tokenCost>0 with
  /// purchasePrice=0 = token-per-play only, both >0 = token-per-play with a buy-outright option
  /// layered on top. Stored in the separate gamePricing map, not on GameSubmission itself (see
  /// gamePricingEntries' comment for why).
  public shared(msg) func adminSetGamePricing(gameId : Text, tokenCost : Nat, purchasePrice : Nat) : async Result.Result<(), Text> {
    assert (not isBannedNow(msg.caller)); // banned: only withdrawals, claims and listing allowed
    if (not isAdmin(msg.caller)) return #err("Admin only");
    hydrateRuntimeStateIfNeeded();
    switch (gameSubmissions.get(gameId)) {
      case null return #err("Game not found");
      case (?_) {};
    };
    ignore tokenCost;
    gamePricing.put(gameId, (1, purchasePrice));
    #ok(())
  };

  /// Creator-requested buy-outright price (tokens), set from the Showroom submission form. Creator only
  /// before the game is live, and only for non-ticket games marked Purchasable; admin anytime. Writes the
  /// same pricing record adminSetGamePricing does, keeping the existing per-play token cost (default 1).
  public shared(msg) func setGameRequestedPurchasePrice(gameId : Text, purchasePrice : Nat) : async Result.Result<(), Text> {
    assert (not isBannedNow(msg.caller)); // banned: only withdrawals, claims and listing allowed
    let caller = msg.caller;
    if (Principal.isAnonymous(caller)) return #err("Must be authenticated");
    hydrateRuntimeStateIfNeeded();
    let game = switch (gameSubmissions.get(gameId)) {
      case null return #err("Game not found");
      case (?g) g;
    };
    let callerIsAdmin = isAdmin(caller);
    if (not Principal.equal(game.creator, caller) and not callerIsAdmin) return #err("Not authorized");
    if (not callerIsAdmin and game.status == "live") return #err("Purchase price can only be set at submission");
    if (purchasePrice == 0) return #err("Purchase price must be at least 1 token");
    switch (gameMonetization.get(gameId)) {
      case (?(paysTickets, wantsPurchasable)) {
        if (paysTickets) return #err("Ticket games can't be purchasable");
        if (not wantsPurchasable) return #err("Game is not marked Purchasable");
      };
      case null { return #err("Set monetization before the purchase price") };
    };
    gamePricing.put(gameId, (1, purchasePrice));
    #ok(())
  };

  public query func getGamePricing(gameId : Text) : async { tokenCost : ?Nat; purchasePrice : ?Nat } {
    switch (gamePricing.get(gameId)) {
      case null { { tokenCost = null; purchasePrice = null } };
      case (?(tc, pp)) {
        ignore tc;
        { tokenCost = ?1; purchasePrice = if (pp == 0) null else ?pp }
      };
    };
  };

  public query func getAllGameCategories() : async [(Text, Text)] {
    Iter.toArray(gameCategories.entries())
  };

  /// Batch getters mirroring getAllGameCategories - the player-facing game cache needs every
  /// game's monetization/pricing in one call, not one query per game per cache refresh.
  public query func getAllGameMonetization() : async [(Text, (Bool, Bool))] {
    Iter.toArray(gameMonetization.entries())
  };

  public query func getAllGamePricing() : async [(Text, (Nat, Nat))] {
    Array.map<(Text, (Nat, Nat)), (Text, (Nat, Nat))>(Iter.toArray(gamePricing.entries()), func((g, (_, pp))) { (g, (1, pp)) })
  };

  /// Admin: reject a queued submission instead of publishing it. Notifies the submitter with the
  /// given reason and clears the associated pending upload (zip or thumbnail — whichever the
  /// admin was reviewing when they rejected).
  public shared(msg) func adminRejectZipGame(gameId : Text, uploadId : Text, reason : Text) : async Result.Result<Text, Text> {
    assert (not isBannedNow(msg.caller)); // banned: only withdrawals, claims and listing allowed
    if (not isAdmin(msg.caller)) return #err("Admin only");
    hydrateRuntimeStateIfNeeded();
    let game = switch (gameSubmissions.get(gameId)) {
      case null return #err("Game not found");
      case (?g) g;
    };
    let updated : GameSubmission = { game with status = "rejected" };
    gameSubmissions.put(gameId, updated);
    let reasonText = if (Text.size(reason) == 0) "No reason given." else reason;
    createNotification(game.creator, "Submission Rejected", "\"" # game.name # "\" was not approved.<br><br>" # reasonText, gameId);
    ignore uploadId; // kept for API compatibility; every upload tied to this game is now swept below
    deleteAllPendingUploadsForGameId(gameId);
    #ok("Game rejected")
  };

  /// Admin: register an already-uploaded game from the admin panel.
  /// The frontend sends richer upload metadata than the current stable
  /// GameSubmission schema stores; intentionally persist only schema-safe
  /// fields for this hotfix to avoid a state-breaking migration.
  public shared(msg) func adminAddGame(
    name : Text,
    developer : Text,
    url : Text,
    thumbnailUrl : Text,
    description : Text,
    compatibility : Text,
    creator : Principal,
    gameTier : Text,
    paysTickets : Bool,
    screenshots : [Text],
    category : Text,
    tokenCost : Nat,
    scoring : Text,
    purchasePrice : Nat
  ) : async Result.Result<Text, Text> {
    if (not isAdmin(msg.caller)) return #err("Not authorized");
    hydrateRuntimeStateIfNeeded();
    if (Text.size(name) == 0) return #err("Name required");
    if (Text.size(url) == 0) return #err("URL required");

    let normalizedTier =
      if (gameTier == "showroom") {
        "showroom";
      } else if (gameTier == "jays-picks") {
        "jays-picks";
      } else {
        "backroom";
      };

    ignore paysTickets;
    ignore screenshots;
    ignore category;
    ignore tokenCost;
    ignore scoring;
    ignore purchasePrice;

    let id = genGameId();
    let game : GameSubmission = {
      id = id;
      name = name;
      developer = developer;
      url = url;
      thumbnailUrl = thumbnailUrl;
      description = description;
      compatibility = compatibility;
      creator = creator;
      gameTier = normalizedTier;
      status = "live";
      feePaid = 0;
      showroomFeePaid = 0;
      txId = 0;
      createdAt = Time.now();
    };
    gameSubmissions.put(id, game);
    #ok(id);
  };

  /// Admin: return every game submission, including removed records.
  public shared(msg) func adminGetAllGames() : async [GameSubmission] {
    assert (not isBannedNow(msg.caller)); // banned: only withdrawals, claims and listing allowed
    if (not isAdmin(msg.caller)) return [];
    hydrateRuntimeStateIfNeeded();
    Iter.toArray(gameSubmissions.vals());
  };

  /// Admin: promote game to Jay's Picks
  public shared(msg) func promoteGameToJaysPicks(gameId : Text) : async Result.Result<Text, Text> {
    assert (not isBannedNow(msg.caller)); // banned: only withdrawals, claims and listing allowed
    if (not isAdmin(msg.caller)) return #err("Not authorized");
    hydrateRuntimeStateIfNeeded();
    switch (gameSubmissions.get(gameId)) {
      case null { return #err("Game not found") };
      case (?game) {
        let updated : GameSubmission = {
          id = game.id; name = game.name; developer = game.developer;
          url = game.url; thumbnailUrl = game.thumbnailUrl; description = game.description;
          compatibility = game.compatibility; creator = game.creator;
          gameTier = "jays-picks"; status = game.status;
          feePaid = game.feePaid; showroomFeePaid = game.showroomFeePaid;
          txId = game.txId; createdAt = game.createdAt;
        };
        gameSubmissions.put(gameId, updated);
        #ok("Game promoted to Jay's Picks!");
      };
    };
  };

  /// Admin: remove game
  public shared(msg) func removeGameSubmission(gameId : Text) : async Result.Result<Text, Text> {
    assert (not isBannedNow(msg.caller)); // banned: only withdrawals, claims and listing allowed
    if (not isAdmin(msg.caller)) return #err("Not authorized");
    hydrateRuntimeStateIfNeeded();
    switch (gameSubmissions.get(gameId)) {
      case null { return #err("Game not found") };
      case (?game) {
        let updated : GameSubmission = {
          id = game.id; name = game.name; developer = game.developer;
          url = game.url; thumbnailUrl = game.thumbnailUrl; description = game.description;
          compatibility = game.compatibility; creator = game.creator;
          gameTier = game.gameTier; status = "removed";
          feePaid = game.feePaid; showroomFeePaid = game.showroomFeePaid;
          txId = game.txId; createdAt = game.createdAt;
        };
        gameSubmissions.put(gameId, updated);
        deleteAllPendingUploadsForGameId(gameId);
        #ok("Game removed. No refund issued.");
      };
    };
  };

  /// Admin: suspend a live game - hides it from public listings (any status !="live" is filtered
  /// out of browse views) without touching its record or hosted files at all. Fully reversible via
  /// adminRelistGame below. Distinct from the older "removed" status above, which has no relist
  /// path - suspend is specifically for "needs work, will come back."
  public shared(msg) func adminSuspendGame(gameId : Text) : async Result.Result<Text, Text> {
    assert (not isBannedNow(msg.caller)); // banned: only withdrawals, claims and listing allowed
    if (not isAdmin(msg.caller)) return #err("Not authorized");
    hydrateRuntimeStateIfNeeded();
    switch (gameSubmissions.get(gameId)) {
      case null { return #err("Game not found") };
      case (?game) {
        let updated : GameSubmission = {
          id = game.id; name = game.name; developer = game.developer;
          url = game.url; thumbnailUrl = game.thumbnailUrl; description = game.description;
          compatibility = game.compatibility; creator = game.creator;
          gameTier = game.gameTier; status = "suspended";
          feePaid = game.feePaid; showroomFeePaid = game.showroomFeePaid;
          txId = game.txId; createdAt = game.createdAt;
        };
        gameSubmissions.put(gameId, updated);
        #ok("Game suspended.");
      };
    };
  };

  /// Admin: set which devices a listed game is shown on: "desktop", "mobile" or "both".
  /// Phones only list games marked "mobile" or "both".
  public shared(msg) func adminSetGameCompatibility(gameId : Text, compatibility : Text) : async Result.Result<Text, Text> {
    assert (not isBannedNow(msg.caller)); // banned: only withdrawals, claims and listing allowed
    if (not isAdmin(msg.caller)) return #err("Not authorized");
    if (compatibility != "desktop" and compatibility != "mobile" and compatibility != "both") return #err("Platform must be desktop, mobile or both");
    hydrateRuntimeStateIfNeeded();
    switch (gameSubmissions.get(gameId)) {
      case null { return #err("Game not found") };
      case (?game) {
        let updated : GameSubmission = {
          id = game.id; name = game.name; developer = game.developer;
          url = game.url; thumbnailUrl = game.thumbnailUrl; description = game.description;
          compatibility = compatibility; creator = game.creator;
          gameTier = game.gameTier; status = game.status;
          feePaid = game.feePaid; showroomFeePaid = game.showroomFeePaid;
          txId = game.txId; createdAt = game.createdAt;
        };
        gameSubmissions.put(gameId, updated);
        #ok("Platform set to " # compatibility);
      };
    };
  };

  /// Admin: relist a previously-suspended game back to live, at no cost - the game was already
  /// paid for once, this is purely a visibility toggle back on. Only allowed from "suspended" so
  /// this can't accidentally resurrect a "removed" or already-live game via the wrong button.
  public shared(msg) func adminRelistGame(gameId : Text) : async Result.Result<Text, Text> {
    assert (not isBannedNow(msg.caller)); // banned: only withdrawals, claims and listing allowed
    if (not isAdmin(msg.caller)) return #err("Not authorized");
    hydrateRuntimeStateIfNeeded();
    switch (gameSubmissions.get(gameId)) {
      case null { return #err("Game not found") };
      case (?game) {
        if (game.status != "suspended") return #err("Game is not suspended: " # game.status);
        // Ticket games need a complete, enabled payout table to go live - otherwise every score pays 0.
        if (isTicketGameSubmission(game)) {
          switch (gamePayoutConfigs.get(gameId)) {
            case null { return #err("Set the payout table before relisting this Ticket game (7 score thresholds) - without one every score pays 0 tickets.") };
            case (?cfg) {
              if (not cfg.enabled or (cfg.thresholds.size() != 7 and cfg.thresholds.size() != 8)) return #err("Enable a complete payout ladder before relisting this Ticket game.");
            };
          };
        };
        let updated : GameSubmission = {
          id = game.id; name = game.name; developer = game.developer;
          url = game.url; thumbnailUrl = game.thumbnailUrl; description = game.description;
          compatibility = game.compatibility; creator = game.creator;
          gameTier = game.gameTier; status = "live";
          feePaid = game.feePaid; showroomFeePaid = game.showroomFeePaid;
          txId = game.txId; createdAt = game.createdAt;
        };
        gameSubmissions.put(gameId, updated);
        #ok("Game relisted.");
      };
    };
  };

  /// Admin: permanently delete a game's record entirely (unlike removeGameSubmission/
  /// adminSuspendGame above, which only ever change status - this actually removes the entry from
  /// gameSubmissions). Does NOT touch the game's hosted files on the asset canister - only the
  /// admin's own wallet has Prepare/Commit permission there, not this backend canister, so that
  /// cleanup happens client-side (see deleteGameFromChain) as a second step in the same admin
  /// action. Also sweeps any lingering pending zip/thumbnail uploads for this game, same as the
  /// existing removeGameSubmission does.
  public shared(msg) func adminDeleteGamePermanently(gameId : Text) : async Result.Result<Text, Text> {
    assert (not isBannedNow(msg.caller)); // banned: only withdrawals, claims and listing allowed
    if (not isAdmin(msg.caller)) return #err("Not authorized");
    hydrateRuntimeStateIfNeeded();
    switch (gameSubmissions.get(gameId)) {
      case null { return #err("Game not found") };
      case (?_) {
        gameSubmissions.delete(gameId);
        deleteAllPendingUploadsForGameId(gameId);
        // Per-game settings keyed by this ID (session #3) - cleared so deletes stop leaving orphans.
        // Deliberately NOT touched: ticket pools, purchases, token spend, paid sessions - those hold
        // real value, and what happens to them on delete is a separate policy decision.
        gameCategories.delete(gameId);
        gameAccessibility.delete(gameId);
        gameMonetization.delete(gameId);
        gamePricing.delete(gameId);
        gamePayoutConfigs.delete(gameId);
        gameTicketJackpotConfigs.delete(gameId);
    jackpotTierModeEntries := Array.filter<(Text, (Bool, Bool))>(jackpotTierModeEntries, func(e) { e.0 != gameId });
    leaderboards.delete(gameId);
    gameTopScoreEntries := Array.filter<(Text, [(Principal, Nat, Int)])>(gameTopScoreEntries, func(e) { e.0 != gameId });
    retiredBreakerEntries := Array.filter<(Text, Principal, Text, Nat, Int)>(retiredBreakerEntries, func(b) { b.0 != gameId });
    for ((pb, pl) in Iter.toArray(playerBests.entries()).vals()) {
      let kept = Array.filter<(Text, Nat, Int)>(pl, func(e) { e.0 != gameId });
      if (kept.size() != pl.size()) { if (kept.size() == 0) { playerBests.delete(pb) } else { playerBests.put(pb, kept) } };
    };
        #ok("Game permanently deleted.");
      };
    };
  };

  /// Get all live game submissions
  public query func getGameSubmissions() : async [GameSubmission] {
    let all = if (runtimeStateHydrated) {
      Iter.toArray(gameSubmissions.vals());
    } else {
      Array.map<(Text, GameSubmission), GameSubmission>(gameSubmissionEntries, func((_, game)) { game });
    };
    Array.filter<GameSubmission>(all, func(g) { g.status == "live" });
  };

  /// Get games by tier
  public query func getGamesByTier(tier : Text) : async [GameSubmission] {
    let all = if (runtimeStateHydrated) {
      Iter.toArray(gameSubmissions.vals());
    } else {
      Array.map<(Text, GameSubmission), GameSubmission>(gameSubmissionEntries, func((_, game)) { game });
    };
    Array.filter<GameSubmission>(all, func(g) { g.status == "live" and g.gameTier == tier });
  };

  /// Record a display/audit receipt after a user's wallet has already sent ICP directly to a game creator.
  public shared({ caller }) func recordIcpTip(
    gameId : Text,
    creator : Principal,
    amountE8s : Nat,
    anonymous : Bool,
    displayName : Text,
    txRef : Text
  ) : async Result.Result<Text, Text> {
    assert (not isBannedNow(caller)); // banned: only withdrawals, claims and listing allowed
    if (Principal.isAnonymous(caller)) return #err("Must be authenticated");
    hydrateRuntimeStateIfNeeded();
    let game = switch (gameSubmissions.get(gameId)) {
      case null return #err("Game not found");
      case (?g) g;
    };
    if (game.status != "live") return #err("Game is not live");
    if (not Principal.equal(game.creator, creator)) return #err("Creator does not match game submission");
    if (amountE8s < ICP_TIP_MIN_E8S) return #err("Tip amount is below the minimum display threshold");
    let receiptId = gameId # "-icp-tip-" # Nat.toText(tipReceipts.size() + 1);
    let receipt : TipReceipt = {
      id = receiptId;
      gameId = gameId;
      creator = creator;
      tipper = caller;
      amountE8s = amountE8s;
      anonymous = anonymous;
      displayName = if (anonymous) "" else displayName;
      txRef = txRef;
      createdAt = Time.now();
    };
    tipReceipts.add(receipt);
    #ok(receiptId);
  };

  public query func getGameIcpTipSummary(gameId : Text) : async IcpTipSummary {
    let source = if (runtimeStateHydrated) { Buffer.toArray(tipReceipts) } else { tipReceiptEntries };
    var total : Nat = 0;
    var count : Nat = 0;
    for (receipt in source.vals()) {
      if (receipt.gameId == gameId) {
        total += receipt.amountE8s;
        count += 1;
      };
    };
    { totalE8s = total; count = count };
  };

  public query func getRecentGameIcpTips(gameId : Text, limit : Nat) : async [TipReceipt] {
    let source = if (runtimeStateHydrated) { Buffer.toArray(tipReceipts) } else { tipReceiptEntries };
    let cappedLimit = if (limit > 25) { 25 } else { limit };
    let out = Buffer.Buffer<TipReceipt>(cappedLimit);
    var i = source.size();
    while (i > 0 and out.size() < cappedLimit) {
      i -= 1;
      let receipt = source[i];
      if (receipt.gameId == gameId) {
        out.add(receipt);
      };
    };
    Buffer.toArray(out);
  };

  // ============================================
  // === MODEL A TICKET ACCOUNTING QUERIES ===
  // ============================================

  /// Internal/admin raw ticket pool counter for a game.
  /// This first pass keeps the state explicit and queryable without rewriting payout economics yet.
  public query func getGameRawTicketPool(gameId : Text) : async Nat {
    getGameRawTicketPoolValue(gameId);
  };

  /// Public-facing backed allocation bucket for a game.
  public query func getGameBackedTicketPool(gameId : Text) : async Nat {
    getGameBackedTicketPoolValue(gameId);
  };

  public query func getAllGameRawTicketPools() : async [GameRawTicketPoolSnapshot] {
    let source = if (runtimeStateHydrated) {
      Iter.toArray(gameRawTicketPools.entries());
    } else {
      gameRawTicketPoolEntries;
    };
    Array.map<(Text, Nat), GameRawTicketPoolSnapshot>(source, func((gameId, rawTicketPool)) {
      { gameId = gameId; rawTicketPool = rawTicketPool };
    });
  };

  /// One call for the game lists: every game's high score plus the record holder's public
  /// name and avatar, so a page with N cards does not make 2N profile/high-score queries.
  /// Query-only: reads the hydrated maps when available, otherwise the stable arrays.
  public query func getGameCardStats() : async [{ gameId : Text; highScore : Nat; holder : Principal; holderName : Text; holderAvatarUrl : Text }] {
    let lb = if (runtimeStateHydrated) { Iter.toArray(leaderboards.entries()) } else { leaderboardEntries };
    Array.map<(Text, LeaderboardEntry), { gameId : Text; highScore : Nat; holder : Principal; holderName : Text; holderAvatarUrl : Text }>(lb, func((gid, e)) {
      let prof = getPlayerProfileOpt(e.player);
      {
        gameId = gid;
        highScore = e.score;
        holder = e.player;
        holderName = switch (prof) { case (?p) p.name; case null "" };
        holderAvatarUrl = switch (prof) { case (?p) p.avatarUrl; case null "" };
      }
    });
  };

  public query func getAllGameBackedTicketPools() : async [GameBackedTicketPoolSnapshot] {
    let source = if (runtimeStateHydrated) {
      Iter.toArray(gameBackedTicketPools.entries());
    } else {
      gameBackedTicketPoolEntries;
    };
    Array.map<(Text, Nat), GameBackedTicketPoolSnapshot>(source, func((gameId, backedTicketPool)) {
      { gameId = gameId; backedTicketPool = backedTicketPool };
    });
  };

  /// Audit/query surface for Model A reserve coverage. Raw is internal accrual,
  /// backed is the public outstanding ticket liability, and backed never falls
  /// back to legacy raw counters after migration.
  public query func getTicketReserveAudit() : async {
    totalRawTicketPool : Nat;
    totalBackedTicketPool : Nat;
    outstandingBackedLiability : Nat;
    coverageGap : Nat;
    surplusBacking : Nat;
    unbackedRawExposure : Nat;
    ticketGameCount : Nat;
  } {
    getTicketReserveAuditSnapshot();
  };

  public query func getRecentTicketJackpotWins(limit : Nat) : async [TicketJackpotWin] {
    let boundedLimit = if (limit > 50) 50 else limit;
    if (boundedLimit == 0) {
      return [];
    };
    let source = if (runtimeStateHydrated) {
      Buffer.toArray(ticketJackpotWins);
    } else {
      ticketJackpotWinEntries;
    };
    let results = Buffer.Buffer<TicketJackpotWin>(boundedLimit);
    var index = source.size();
    while (index > 0 and results.size() < boundedLimit) {
      index -= 1;
      results.add(source[index]);
    };
    Buffer.toArray(results);
  };

  public query func getRecentTicketJackpotWinDetails(limit : Nat) : async [TicketJackpotWinDetail] {
    let boundedLimit = if (limit > 50) 50 else limit;
    let source = if (runtimeStateHydrated) {
      Buffer.toArray(ticketJackpotWinDetails);
    } else {
      ticketJackpotWinTierEntries;
    };
    let results = Buffer.Buffer<TicketJackpotWinDetail>(boundedLimit);
    var index = source.size();
    while (index > 0 and results.size() < boundedLimit) {
      index -= 1;
      results.add(source[index]);
    };
    Buffer.toArray(results);
  };

  public query func getGameTicketJackpotSnapshot(gameId : Text) : async { backedTicketPool : Nat; maxPossibleJackpot : Nat } {
    let backedTicketPool = getGameBackedTicketPoolValue(gameId);
    let maxPossibleJackpot = switch (if (runtimeStateHydrated) { gameTicketJackpotConfigs.get(gameId) } else { stableGameTicketJackpotConfig(gameId) }) {
      case null 0;
      case (?config) {
        let modes = jackpotTierModes(gameId);
        let lowAmt = jackpotTierUncapped(config.lowPayoutPercent, modes.0, backedTicketPool);
        let highAmt = if (config.highPayoutPercent > 0) { jackpotTierUncapped(config.highPayoutPercent, modes.1, backedTicketPool) } else { 0 };
        let tierMax = if (highAmt > lowAmt) { highAmt } else { lowAmt };
        let recordAmt = backedTicketPool * config.newHighScorePayoutPercent / 10_000;
        capTicketJackpotPayout(tierMax + recordAmt, backedTicketPool, DAILY_TICKET_CAP);
      };
    };
    {
      backedTicketPool = backedTicketPool;
      maxPossibleJackpot = maxPossibleJackpot;
    };
  };

  // ============================================
  // === CREATOR ROYALTIES ===
  // ============================================

  /// Legacy-compatible game creator royalty balance query (ICP owed, in e8s).
  /// NFT seller earnings stay in a separate bucket and are exposed by getNftSellerEarnings/getClaimableEarningsBreakdown.
  public query func getRoyalties(creator : Principal) : async Nat {
    getGameCreatorEarningsBalance(creator);
  };

  public query func getGameCreatorEarnings(creator : Principal) : async Nat {
    getGameCreatorEarningsBalance(creator);
  };

  public query func getNftSellerEarnings(seller : Principal) : async Nat {
    getNftSellerEarningsBalance(seller);
  };

  public query func getClaimableEarningsBreakdown(account : Principal) : async ClaimableEarningsBreakdown {
    let gameCreatorEarningsE8s = getGameCreatorEarningsBalance(account);
    let nftSellerEarningsE8sValue = getNftSellerEarningsBalance(account);
    let refundE8s = getRefundBalance(account);
    {
      gameCreatorEarningsE8s = gameCreatorEarningsE8s;
      nftSellerEarningsE8s = nftSellerEarningsE8sValue;
      refundE8s = refundE8s;
      totalClaimableE8s = gameCreatorEarningsE8s + nftSellerEarningsE8sValue + refundE8s;
    };
  };

  /// Admin: credit game creator earnings to a creator. This intentionally does not credit NFT seller earnings.
  public shared(msg) func creditRoyalty(creator : Principal, amountE8s : Nat) : async Result.Result<Nat, Text> {
    assert (not isBannedNow(msg.caller)); // banned: only withdrawals, claims and listing allowed
    if (not ALLOW_TEST_MINTING) return #err("Test minting is disabled on this network");
    if (not isAdmin(msg.caller)) return #err("Not authorized");
    hydrateRuntimeStateIfNeeded();
    let current = getGameCreatorEarningsBalance(creator);
    let newBal = current + amountE8s;
    royalties.put(creator, newBal);
    #ok(newBal);
  };

  /// Get fixed economy conversion rates and canonical seller payout examples.
  public query func getEconomyRates() : async EconomyRates {
    {
      icpE8s = ICP_E8S;
      tokensPerIcp = TOKENS_PER_ICP;
      ticketsPerIcp = TICKETS_PER_ICP;
      tokenE8s = TOKEN_LIABILITY_E8S;
      ticketE8s = TICKET_LIABILITY_E8S;
      sellerPayout100TicketsE8s = ticketCostToSellerPayoutE8s(100);
      sellerPayout1000TicketsE8s = ticketCostToSellerPayoutE8s(1000);
    };
  };

  /// Get revenue split percentages (Economy v6). Confirmed zero frontend callers before this
  /// field rename (ticketGameBurnShare/regularGameBurnShare -> ...ArcadeShare) - safe to rename
  /// since nothing decodes this response today.
  public query func getRevenueSplits() : async {
    ticketGameCreatorShare : Nat;
    ticketGameDaoShare : Nat;
    ticketGameArcadeShare : Nat;
    ticketGamePoolShare : Nat;
    regularGameCreatorShare : Nat;
    regularGameDaoShare : Nat;
    regularGameArcadeShare : Nat;
    gameCreatorShare : Nat;
    gameCreatorNonTicketShare : Nat;
    nftCreatorShare : Nat;
  } {
    {
      ticketGameCreatorShare = TICKET_GAME_CREATOR_SHARE;
      ticketGameDaoShare = TICKET_GAME_DAO_SHARE;
      ticketGameArcadeShare = TICKET_GAME_ARCADE_SHARE;
      ticketGamePoolShare = TICKET_GAME_POOL_SHARE;
      regularGameCreatorShare = REGULAR_GAME_CREATOR_SHARE;
      regularGameDaoShare = REGULAR_GAME_DAO_SHARE;
      regularGameArcadeShare = REGULAR_GAME_ARCADE_SHARE;
      gameCreatorShare = TICKET_GAME_CREATOR_SHARE;
      gameCreatorNonTicketShare = REGULAR_GAME_CREATOR_SHARE;
      nftCreatorShare = NFT_CREATOR_SHARE;
    };
  };

  /// Creator/seller claims accumulated ICP-denominated game creator earnings, NFT seller earnings, plus separated ICP refunds.
  /// Funds move from the canister main treasury account into the caller's derived subaccount,
  /// after which the normal withdraw UI can send ICP to any principal or account ID.
  /// Claim only the creator earnings balance (the combined claimRoyalties button still pays everything).
  public shared(msg) func claimCreatorEarningsOnly() : async Result.Result<Nat, Text> {
    let caller = msg.caller;
    if (Principal.isAnonymous(caller)) return #err("Must be authenticated");
    hydrateRuntimeStateIfNeeded();
    let balance = getGameCreatorEarningsBalance(caller);
    if (balance == 0) return #err("No claimable creator earnings");
    if (balance < ROYALTY_CLAIM_MIN_E8S) {
      return #err(
        "Minimum claim is " # Nat.toText(ROYALTY_CLAIM_MIN_E8S) #
        " e8s; current creator earnings balance is " # Nat.toText(balance) # " e8s"
      );
    };
    // Debit before the ledger await so an overlapping claim sees zero and cannot double-pay.
    royalties.put(caller, 0);
    try {
      let result = await ICP_LEDGER.icrc1_transfer({
        to = { owner = caller; subaccount = null };
        fee = ?ICP_LEDGER_FEE_E8S;
        memo = null;
        from_subaccount = null;
        created_at_time = ?ledgerNow();
        amount = balance - ICP_LEDGER_FEE_E8S; // claimant pays the ledger fee
      });
      switch (result) {
        case (#Ok(_blockIndex)) { #ok(balance - ICP_LEDGER_FEE_E8S) };
        case (#Err(e)) {
          restoreGameCreatorEarningsBalance(caller, balance);
          switch (e) {
            case (#InsufficientFunds(f)) {
              #err("Treasury has insufficient funds: " # Nat.toText(f.balance) # " e8s available")
            };
            case (#BadFee(f)) {
              #err("Bad fee while claiming creator earnings: expected " # Nat.toText(f.expected_fee))
            };
            case (#GenericError(ge)) {
              #err("Ledger error " # Nat.toText(ge.error_code) # ": " # ge.message)
            };
            case (_) { #err("Claim transfer failed") };
          }
        };
      }
    } catch (e) {
      restoreGameCreatorEarningsBalance(caller, balance);
      #err("Claim transfer error: " # Error.message(e))
    }
  };

  /// Claim only the NFT seller earnings balance (the combined claimRoyalties button still pays everything).
  public shared(msg) func claimNftSellerEarningsOnly() : async Result.Result<Nat, Text> {
    let caller = msg.caller;
    if (Principal.isAnonymous(caller)) return #err("Must be authenticated");
    hydrateRuntimeStateIfNeeded();
    let balance = getNftSellerEarningsBalance(caller);
    if (balance == 0) return #err("No claimable NFT seller earnings");
    if (balance < ROYALTY_CLAIM_MIN_E8S) {
      return #err(
        "Minimum claim is " # Nat.toText(ROYALTY_CLAIM_MIN_E8S) #
        " e8s; current NFT seller earnings balance is " # Nat.toText(balance) # " e8s"
      );
    };
    // Debit before the ledger await so an overlapping claim sees zero and cannot double-pay.
    nftSellerEarningsE8s.put(caller, 0);
    try {
      let result = await ICP_LEDGER.icrc1_transfer({
        to = { owner = caller; subaccount = null };
        fee = ?ICP_LEDGER_FEE_E8S;
        memo = null;
        from_subaccount = null;
        created_at_time = ?ledgerNow();
        amount = balance - ICP_LEDGER_FEE_E8S; // claimant pays the ledger fee
      });
      switch (result) {
        case (#Ok(_blockIndex)) { #ok(balance - ICP_LEDGER_FEE_E8S) };
        case (#Err(e)) {
          restoreNftSellerEarningsBalance(caller, balance);
          switch (e) {
            case (#InsufficientFunds(f)) {
              #err("Treasury has insufficient funds: " # Nat.toText(f.balance) # " e8s available")
            };
            case (#BadFee(f)) {
              #err("Bad fee while claiming NFT seller earnings: expected " # Nat.toText(f.expected_fee))
            };
            case (#GenericError(ge)) {
              #err("Ledger error " # Nat.toText(ge.error_code) # ": " # ge.message)
            };
            case (_) { #err("Claim transfer failed") };
          }
        };
      }
    } catch (e) {
      restoreNftSellerEarningsBalance(caller, balance);
      #err("Claim transfer error: " # Error.message(e))
    }
  };

  public shared(msg) func claimRoyalties() : async Result.Result<Nat, Text> {
    let caller = msg.caller;
    if (Principal.isAnonymous(caller)) return #err("Must be authenticated");
    hydrateRuntimeStateIfNeeded();
    let gameCreatorEarningsBalance = getGameCreatorEarningsBalance(caller);
    let nftSellerEarningsBalance = getNftSellerEarningsBalance(caller);
    let refundBalance = getRefundBalance(caller);
    let balance = gameCreatorEarningsBalance + nftSellerEarningsBalance + refundBalance;
    if (balance == 0) return #err("No claimable creator/seller earnings or refunds");
    if (balance < ROYALTY_CLAIM_MIN_E8S) {
      return #err(
        "Minimum royalty claim is " # Nat.toText(ROYALTY_CLAIM_MIN_E8S) #
        " e8s; current balance is " # Nat.toText(balance) # " e8s"
      );
    };

    // Lock/debit before any ledger await. Motoko re-entry only happens at await
    // points, so a repeated or overlapping claim sees zero and cannot double-pay.
    royalties.put(caller, 0);
    nftSellerEarningsE8s.put(caller, 0);
    refundsE8s.put(caller, 0);

    try {
      let result = await ICP_LEDGER.icrc1_transfer({
        to = { owner = caller; subaccount = null }; // session #3: creator's own principal account (managed on Creator Earnings)
        fee = ?ICP_LEDGER_FEE_E8S;
        memo = null;
        from_subaccount = null;
        created_at_time = ?ledgerNow();
        amount = balance - ICP_LEDGER_FEE_E8S; // claimant pays the ledger fee
      });
      switch (result) {
        case (#Ok(_blockIndex)) {
          #ok(balance - ICP_LEDGER_FEE_E8S);
        };
        case (#Err(e)) {
          restoreGameCreatorEarningsBalance(caller, gameCreatorEarningsBalance);
          restoreNftSellerEarningsBalance(caller, nftSellerEarningsBalance);
          restoreRefundBalance(caller, refundBalance);
          switch (e) {
            case (#InsufficientFunds(f)) {
              #err("Treasury has insufficient funds: " # Nat.toText(f.balance) # " e8s available")
            };
            case (#BadFee(f)) {
              #err("Bad fee while claiming royalties: expected " # Nat.toText(f.expected_fee))
            };
            case (#GenericError(ge)) {
              #err("Ledger error " # Nat.toText(ge.error_code) # ": " # ge.message)
            };
            case (_) { #err("Royalty claim transfer failed") };
          }
        };
      }
    } catch (e) {
      restoreGameCreatorEarningsBalance(caller, gameCreatorEarningsBalance);
      restoreNftSellerEarningsBalance(caller, nftSellerEarningsBalance);
      restoreRefundBalance(caller, refundBalance);
      #err("Royalty claim transfer error: " # Error.message(e))
    }
  };

  // ============================================
  // === TOKEN TIPS (The Back) ===
  // Tokens are already fully backed 1:1 by real ICP already in canister custody (verified in the
  // solvency audit), so a Token tip converts at the same 1 ICP = 100 Tokens rate used everywhere
  // else and credits a genuinely separate claimable pool from royalties — kept apart per Jay's
  // explicit request, rather than merged into the existing royalties balance. Real ICP tips
  // (recordIcpTip) are deliberately left untouched: those go directly wallet-to-wallet and were
  // never routed through canister custody, so there is nothing to claim for that path.
  let TOKEN_TIP_E8S_PER_TOKEN : Nat = 1_000_000; // 100 Tokens = 1 ICP, same rate as convertDepositToTokens

  // === SEND TOKENS: players gift Tokens to each other (free, max 1,000 sent per rolling 24h). Tickets never move. ===
  stable var tokenTransferLog : [(Principal, Principal, Nat, Int)] = []; // (from, to, amount, at), newest last
  transient let TOKEN_SEND_DAILY_LIMIT : Nat = 1_000;
  transient let TOKEN_TRANSFER_LOG_MAX : Nat = 10_000;
  func tokensSentLast24h(p : Principal, now : Int) : Nat {
    var n : Nat = 0;
    for ((f, _, a, at) in tokenTransferLog.vals()) {
      if (Principal.equal(f, p) and now - at < 86_400_000_000_000) { n += a };
    };
    n
  };
  public shared(msg) func sendTokens(to : Principal, amount : Nat) : async Result.Result<Nat, Text> {
    let caller = msg.caller;
    if (Principal.isAnonymous(caller)) return #err("Must be authenticated");
    if (isBannedNow(caller)) return #err("Your account is suspended");
    hydrateRuntimeStateIfNeeded();
    if (amount == 0) return #err("Enter how many Tokens to send");
    if (Principal.isAnonymous(to) or Principal.equal(to, caller)) return #err("Choose another player to send to");
    if (isBannedNow(to)) return #err("That player can't receive Tokens right now");
    switch (getPlayerProfileOpt(to)) {
      case null { return #err("No player found with that ID. Check it and try again.") };
      case (?pr) { if (Text.size(pr.name) == 0) return #err("No player found with that ID. Check it and try again.") };
    };
    let now = Time.now();
    let sent = tokensSentLast24h(caller, now);
    if (sent + amount > TOKEN_SEND_DAILY_LIMIT) {
      let left : Nat = if (sent >= TOKEN_SEND_DAILY_LIMIT) { 0 } else { TOKEN_SEND_DAILY_LIMIT - sent };
      return #err("Daily send limit is " # Nat.toText(TOKEN_SEND_DAILY_LIMIT) # " Tokens. You can send " # Nat.toText(left) # " more in the next 24 hours.");
    };
    let bal = getTokenBalance(caller);
    if (bal < amount) return #err("Not enough Tokens. You have " # Nat.toText(bal));
    // No await anywhere in this function, so the debit and credit happen together.
    tokens.put(caller, bal - amount);
    tokens.put(to, getTokenBalance(to) + amount);
    var log = tokenTransferLog;
    if (log.size() >= TOKEN_TRANSFER_LOG_MAX) {
      let drop : Nat = log.size() + 1 - TOKEN_TRANSFER_LOG_MAX;
      let old = log;
      log := Array.tabulate<(Principal, Principal, Nat, Int)>(old.size() - drop, func(i) { old[i + drop] });
    };
    tokenTransferLog := Array.append<(Principal, Principal, Nat, Int)>(log, [(caller, to, amount, now)]);
    #ok(bal - amount)
  };
  public shared query(msg) func getMyTokenTransfers() : async { sentLast24h : Nat; dailyLimit : Nat; history : [(Principal, Principal, Nat, Int)] } {
    let p = msg.caller;
    let out = Buffer.Buffer<(Principal, Principal, Nat, Int)>(20);
    var i = tokenTransferLog.size();
    while (i > 0 and out.size() < 20) {
      i -= 1;
      let e = tokenTransferLog[i];
      if (Principal.equal(e.0, p) or Principal.equal(e.1, p)) { out.add(e) };
    };
    { sentLast24h = tokensSentLast24h(p, Time.now()); dailyLimit = TOKEN_SEND_DAILY_LIMIT; history = Buffer.toArray(out) }
  };
  public shared query(msg) func adminGetTokenTransfers(limit : Nat) : async [(Principal, Principal, Nat, Int)] {
    if (not isAdmin(msg.caller)) return [];
    let n = tokenTransferLog.size();
    let k = if (limit < n) { limit } else { n };
    Array.tabulate<(Principal, Principal, Nat, Int)>(k, func(i) { tokenTransferLog[n - 1 - i] }) // newest first
  };

  public shared(msg) func tipCreatorWithTokens(gameId : Text, tokenAmount : Nat) : async Result.Result<Text, Text> {
    assert (not isBannedNow(msg.caller)); // banned: only withdrawals, claims and listing allowed
    let caller = msg.caller;
    if (Principal.isAnonymous(caller)) return #err("Must be authenticated");
    if (tokenAmount == 0) return #err("Tip amount must be greater than zero");
    hydrateRuntimeStateIfNeeded();
    let game = switch (gameSubmissions.get(gameId)) {
      case null return #err("Game not found");
      case (?g) g;
    };
    if (game.status != "live") return #err("Game is not live");
    if (Principal.equal(game.creator, caller)) return #err("You cannot tip your own game");
    let balance = getTokenBalance(caller);
    if (balance < tokenAmount) {
      return #err("Not enough Tokens. Have " # Nat.toText(balance) # ", need " # Nat.toText(tokenAmount));
    };
    tokens.put(caller, balance - tokenAmount);
    let tipE8s = tokenAmount * TOKEN_TIP_E8S_PER_TOKEN;
    restoreTipEarningsBalance(game.creator, tipE8s);
    #ok("Tip sent")
  };

  public query func getTipEarningsBalanceOf(creator : Principal) : async Nat {
    getTipEarningsBalance(creator)
  };

  /// Claims the caller's Token-tip earnings pool only — deliberately separate from claimRoyalties,
  /// per Jay's request for a distinct claim button on the creator earnings page.
  // ============================================
  // === AUTO-PAYOUT: earnings paid every 14 days to a creator-chosen address (48h delay on changes) ===
  type PayoutDest = { kind : Text; owner : ?Principal; subaccount : ?Blob; accountHex : Text };
  type AutoPayoutCfg = { dest : ?PayoutDest; pending : ?PayoutDest; pendingAt : Int; enabled : Bool; lastPayoutAt : Int; lastAmount : Nat; lastResult : Text; failures : Nat };
  type AutoPayoutView = { destLabel : Text; pendingLabel : Text; pendingEffectiveAt : Int; enabled : Bool; nextPayoutAt : Int; lastPayoutAt : Int; lastAmount : Nat; lastResult : Text; failures : Nat };
  stable var autoPayoutEntries : [(Principal, AutoPayoutCfg)] = [];
  transient let AUTO_PAYOUT_INTERVAL_NS : Int = 1_209_600_000_000_000; // 14 days
  transient let AUTO_PAYOUT_DELAY_NS : Int = 172_800_000_000_000; // 48 hours
  transient let AUTO_PAYOUT_MAX_PER_TICK : Nat = 20;
  transient let AUTO_PAYOUT_MAX_FAILURES : Nat = 3;
  transient var autoPayoutBusySince : Int = 0;
  // Auto-payout retry stamps: a failed attempt keeps its created_at_time so the hourly retry
  // re-sends the identical transfer. If the first one actually landed, the ledger answers
  // #Duplicate and we record it as paid instead of paying again. Cleared on success.
  transient var autoPayoutStamp : [(Principal, Nat64)] = [];
  func payoutStampOf(p : Principal) : Nat64 {
    for ((q, t) in autoPayoutStamp.vals()) { if (Principal.equal(q, p)) return t };
    let t = ledgerNow();
    autoPayoutStamp := Array.append<(Principal, Nat64)>(autoPayoutStamp, [(p, t)]);
    t
  };
  func clearPayoutStamp(p : Principal) {
    autoPayoutStamp := Array.filter<(Principal, Nat64)>(autoPayoutStamp, func((q, _)) { not Principal.equal(q, p) });
  };
  transient let LEGACY_ICP_LEDGER : actor { transfer : shared {
    to : Blob; fee : { e8s : Nat64 }; memo : Nat64;
    from_subaccount : ?Blob; created_at_time : ?{ timestamp_nanos : Nat64 };
    amount : { e8s : Nat64 }
  } -> async { #Ok : Nat64; #Err : {
    #BadFee : { expected_fee : { e8s : Nat64 } };
    #InsufficientFunds : { balance : { e8s : Nat64 } };
    #TxTooOld : { allowed_window_nanos : Nat64 };
    #TxCreatedInFuture; #TxDuplicate : { duplicate_of : Nat64 }
  }} } = actor("ryjl3-tyaaa-aaaaa-aaaba-cai");
  func emptyAutoPayout() : AutoPayoutCfg { { dest = null; pending = null; pendingAt = 0; enabled = false; lastPayoutAt = 0; lastAmount = 0; lastResult = ""; failures = 0 } };
  func autoPayoutOf(p : Principal) : AutoPayoutCfg {
    for ((k, v) in autoPayoutEntries.vals()) { if (Principal.equal(k, p)) return v };
    emptyAutoPayout()
  };
  func putAutoPayout(p : Principal, c : AutoPayoutCfg) {
    let rest = Array.filter<(Principal, AutoPayoutCfg)>(autoPayoutEntries, func(e) { not Principal.equal(e.0, p) });
    autoPayoutEntries := Array.append<(Principal, AutoPayoutCfg)>(rest, [(p, c)]);
  };
  func payoutDestLabel(d : ?PayoutDest) : Text {
    switch (d) {
      case null { "" };
      case (?x) {
        if (x.kind == "account") { "Account ID " # x.accountHex } else {
          let o = switch (x.owner) { case (?op) { Principal.toText(op) }; case null { "?" } };
          switch (x.subaccount) { case (?sb) { o # " (subaccount " # blobToHex(sb) # ")" }; case null { o } }
        }
      };
    }
  };
  func autoPayoutViewOf(c : AutoPayoutCfg) : AutoPayoutView {
    let base = if (c.lastPayoutAt > 0) { c.lastPayoutAt } else { Time.now() };
    { destLabel = payoutDestLabel(c.dest); pendingLabel = payoutDestLabel(c.pending);
      pendingEffectiveAt = if (c.pending == null) { 0 } else { c.pendingAt + AUTO_PAYOUT_DELAY_NS };
      enabled = c.enabled; nextPayoutAt = if (c.enabled) { base + AUTO_PAYOUT_INTERVAL_NS } else { 0 };
      lastPayoutAt = c.lastPayoutAt; lastAmount = c.lastAmount; lastResult = c.lastResult; failures = c.failures }
  };
  public shared(msg) func requestAutoPayoutDestination(kind : Text, owner : ?Principal, subaccountHex : Text, accountHex : Text) : async Result.Result<Text, Text> {
    let caller = msg.caller;
    if (Principal.isAnonymous(caller)) return #err("Must be authenticated");
    let dest : PayoutDest = if (kind == "principal") {
      let o = switch (owner) { case (?x) { x }; case null { return #err("Enter a principal") } };
      if (Principal.isAnonymous(o)) return #err("Invalid principal");
      let sub : ?Blob = if (subaccountHex == "") { null } else {
        switch (hexToBlob(subaccountHex)) { case (?b) { if (b.size() != 32) return #err("Subaccount must be 32 bytes (64 hex characters)"); ?b }; case null { return #err("Invalid subaccount") } }
      };
      { kind = "principal"; owner = ?o; subaccount = sub; accountHex = "" }
    } else if (kind == "account") {
      switch (hexToBlob(accountHex)) { case (?b) { if (b.size() != 32) return #err("Account ID must be 64 hex characters") }; case null { return #err("Invalid account ID") } };
      { kind = "account"; owner = null; subaccount = null; accountHex = accountHex }
    } else { return #err("Unknown destination type") };
    let c = autoPayoutOf(caller);
    putAutoPayout(caller, { c with pending = ?dest; pendingAt = Time.now() });
    #ok("New payout address saved. It becomes active in 48 hours unless you cancel it.")
  };
  public shared(msg) func cancelAutoPayoutChange() : async Result.Result<Text, Text> {
    let c = autoPayoutOf(msg.caller);
    if (c.pending == null) return #err("No pending change");
    putAutoPayout(msg.caller, { c with pending = null; pendingAt = 0 });
    #ok("Pending address change cancelled")
  };
  public shared(msg) func setAutoPayoutEnabled(on : Bool) : async Result.Result<Text, Text> {
    if (Principal.isAnonymous(msg.caller)) return #err("Must be authenticated");
    let c = autoPayoutOf(msg.caller);
    if (on and c.dest == null) return #err("Set a payout address first. It becomes active 48 hours after you save it.");
    putAutoPayout(msg.caller, { c with enabled = on; failures = if (on) { 0 } else { c.failures }; lastPayoutAt = if (on and c.lastPayoutAt == 0) { Time.now() } else { c.lastPayoutAt } });
    #ok(if (on) { "Auto-payout on" } else { "Auto-payout off" })
  };
  public shared query(msg) func getMyAutoPayout() : async AutoPayoutView { autoPayoutViewOf(autoPayoutOf(msg.caller)) };
  public shared query(msg) func adminGetAutoPayouts() : async [(Principal, AutoPayoutView)] {
    if (not isAdmin(msg.caller)) return [];
    Array.map<(Principal, AutoPayoutCfg), (Principal, AutoPayoutView)>(autoPayoutEntries, func(e) { (e.0, autoPayoutViewOf(e.1)) })
  };
  // Pays one creator: all four balances in one transfer, zeroed first and restored on failure (same pattern as manual claims).
  func payOutCreator(p : Principal, dest : PayoutDest) : async () {
    let g = getGameCreatorEarningsBalance(p);
    let sl = getNftSellerEarningsBalance(p);
    let rf = getRefundBalance(p);
    let tp = getTipEarningsBalance(p);
    let total = g + sl + rf + tp;
    let now = Time.now();
    if (total < ROYALTY_CLAIM_MIN_E8S) {
      let c0 = autoPayoutOf(p);
      putAutoPayout(p, { c0 with lastPayoutAt = now; lastAmount = 0; lastResult = "Nothing to pay (below the 0.0002 ICP minimum)" });
      return;
    };
    royalties.put(p, 0); nftSellerEarningsE8s.put(p, 0); refundsE8s.put(p, 0); tipEarnings.put(p, 0);
    let amount : Nat = total - ICP_LEDGER_FEE_E8S;
    var ok = false;
    var errText = "Transfer rejected";
    try {
      if (dest.kind == "account") {
        switch (hexToBlob(dest.accountHex)) {
          case (?to) {
            let r = await LEGACY_ICP_LEDGER.transfer({ to = to; fee = { e8s = 10_000 : Nat64 }; memo = 0 : Nat64; from_subaccount = null; created_at_time = ?{ timestamp_nanos = payoutStampOf(p) }; amount = { e8s = Nat64.fromNat(amount) } });
            switch (r) {
              case (#Ok(_)) { ok := true };
              case (#Err(#TxDuplicate(_))) { ok := true }; // the earlier attempt landed: already paid
              case (#Err(#TxTooOld(_))) { clearPayoutStamp(p); errText := "Retry window passed; will retry with a fresh transfer" };
              case (#Err(_)) { errText := "Ledger rejected the transfer (check the account ID)" };
            };
          };
          case null { errText := "Invalid account ID" };
        };
      } else {
        switch (dest.owner) {
          case (?o) {
            let r = await ICP_LEDGER.icrc1_transfer({ to = { owner = o; subaccount = dest.subaccount }; fee = ?ICP_LEDGER_FEE_E8S; memo = null; from_subaccount = null; created_at_time = ?payoutStampOf(p); amount = amount });
            switch (r) {
              case (#Ok(_)) { ok := true };
              case (#Err(#Duplicate(_))) { ok := true }; // the earlier attempt landed: already paid
              case (#Err(#TooOld)) { clearPayoutStamp(p); errText := "Retry window passed; will retry with a fresh transfer" };
              case (#Err(_)) { errText := "Ledger rejected the transfer" };
            };
          };
          case null { errText := "Missing principal" };
        };
      };
    } catch (e) { errText := "Transfer error: " # Error.message(e) };
    let c = autoPayoutOf(p);
    if (ok) {
      clearPayoutStamp(p);
      putAutoPayout(p, { c with lastPayoutAt = now; lastAmount = amount; lastResult = "Paid"; failures = 0 });
    } else {
      restoreGameCreatorEarningsBalance(p, g); restoreNftSellerEarningsBalance(p, sl); restoreRefundBalance(p, rf); restoreTipEarningsBalance(p, tp);
      let f = c.failures + 1;
      let off = f >= AUTO_PAYOUT_MAX_FAILURES;
      putAutoPayout(p, { c with failures = f; enabled = (c.enabled and not off); lastResult = "Failed: " # errText # (if (off) { " - auto-payout turned off after 3 failures" } else { " - will retry" }) });
    };
  };
  // TESTING ONLY (remove before mainnet): activate a pending payout address now and pay this player immediately.
  public shared(msg) func adminTestAutoPayoutNow(p : Principal) : async Result.Result<Text, Text> {
    if (not isAdmin(msg.caller)) return #err("Admin only");
    hydrateRuntimeStateIfNeeded();
    var c = autoPayoutOf(p);
    switch (c.pending) { case (?d) { c := { c with dest = ?d; pending = null; pendingAt = 0; failures = 0 } }; case null {} };
    putAutoPayout(p, c);
    let d = switch (c.dest) { case (?x) { x }; case null { return #err("No payout address set for this player") } };
    await payOutCreator(p, d);
    let after = autoPayoutOf(p);
    #ok(after.lastResult # " | amount " # Nat.toText(after.lastAmount) # " e8s")
  };
  func autoPayoutTick() : async () {
    if (autoPayoutEntries.size() == 0) return; // nobody uses auto-payout: almost free
    let now = Time.now();
    if (autoPayoutBusySince > 0 and now - autoPayoutBusySince < 1_800_000_000_000) return; // self-healing lock (30 min)
    // One pass: activate address changes older than 48h and collect payouts that are due (bounded).
    var changed = false;
    let next = Buffer.Buffer<(Principal, AutoPayoutCfg)>(autoPayoutEntries.size());
    let due = Buffer.Buffer<(Principal, PayoutDest)>(8);
    for ((p, c0) in autoPayoutEntries.vals()) {
      var c = c0;
      switch (c.pending) {
        case (?d) { if (now >= c.pendingAt + AUTO_PAYOUT_DELAY_NS) { c := { c with dest = ?d; pending = null; pendingAt = 0; failures = 0 }; changed := true } };
        case null {};
      };
      if (due.size() < AUTO_PAYOUT_MAX_PER_TICK and c.enabled and now >= c.lastPayoutAt + AUTO_PAYOUT_INTERVAL_NS) {
        switch (c.dest) { case (?d) { due.add((p, d)) }; case null {} };
      };
      next.add((p, c));
    };
    if (changed) { autoPayoutEntries := Buffer.toArray(next) }; // rewrite at most once
    if (due.size() == 0) return; // most hourly checks end here, before any state loading
    autoPayoutBusySince := now;
    hydrateRuntimeStateIfNeeded();
    for ((p, d) in due.vals()) {
      try { await payOutCreator(p, d) } catch (_) {};
    };
    autoPayoutBusySince := 0;
  };

  public shared(msg) func claimTipEarnings() : async Result.Result<Nat, Text> {
    let caller = msg.caller;
    if (Principal.isAnonymous(caller)) return #err("Must be authenticated");
    hydrateRuntimeStateIfNeeded();
    let balance = getTipEarningsBalance(caller);
    if (balance == 0) return #err("No claimable tip earnings");
    if (balance < ROYALTY_CLAIM_MIN_E8S) {
      return #err(
        "Minimum tip claim is " # Nat.toText(ROYALTY_CLAIM_MIN_E8S) #
        " e8s; current balance is " # Nat.toText(balance) # " e8s"
      );
    };
    tipEarnings.put(caller, 0);
    try {
      let result = await ICP_LEDGER.icrc1_transfer({
        to = { owner = caller; subaccount = null }; // session #3: creator's own principal account (managed on Creator Earnings)
        fee = ?ICP_LEDGER_FEE_E8S;
        memo = null;
        from_subaccount = null;
        created_at_time = ?ledgerNow();
        amount = balance - ICP_LEDGER_FEE_E8S; // claimant pays the ledger fee
      });
      switch (result) {
        case (#Ok(_blockIndex)) { #ok(balance - ICP_LEDGER_FEE_E8S) };
        case (#Err(e)) {
          restoreTipEarningsBalance(caller, balance);
          switch (e) {
            case (#InsufficientFunds(f)) {
              #err("Treasury has insufficient funds: " # Nat.toText(f.balance) # " e8s available")
            };
            case (#BadFee(f)) {
              #err("Bad fee while claiming tip earnings: expected " # Nat.toText(f.expected_fee))
            };
            case (#GenericError(ge)) {
              #err("Ledger error " # Nat.toText(ge.error_code) # ": " # ge.message)
            };
            case (_) { #err("Tip claim transfer failed") };
          }
        };
      }
    } catch (e) {
      restoreTipEarningsBalance(caller, balance);
      #err("Tip claim transfer error: " # Error.message(e))
    }
  };

  /// Lifetime total of real ICP sent directly to this creator via the wallet-to-wallet ICP tip
  /// path, across every game they've created — for the display-only "ICP received via tips" box
  /// on the creator earnings page. This ICP was never in canister custody, so there is nothing to
  /// claim here; it's purely informational.
  public query func getCreatorIcpTipTotal(creator : Principal) : async Nat {
    let source = if (runtimeStateHydrated) { Buffer.toArray(tipReceipts) } else { tipReceiptEntries };
    var total : Nat = 0;
    for (receipt in source.vals()) {
      if (Principal.equal(receipt.creator, creator)) { total += receipt.amountE8s };
    };
    total
  };

  // ============================================
  // === NFT ESCROW (ICRC-7) ===
  // ============================================

  /// Confirm DIP-721 NFT escrow — verifies ownerOfDip721 returns this canister
  public shared(msg) func confirmDip721Escrow(listingId : Text, canisterId : Text, tokenId : Nat64) : async Result.Result<Text, Text> {
    let caller = msg.caller;
    if (Principal.isAnonymous(caller)) return #err("Must be authenticated");
    hydrateRuntimeStateIfNeeded();
    switch (nftListings.get(listingId)) {
      case null { return #err("Listing not found: " # listingId) };
      case (?listing) {
        if (not Principal.equal(listing.creator, caller) and not isAdmin(caller)) return #err("Not the listing owner");
        switch (escrows.get(listingId)) {
          case (?existing) {
            if (existing.status == "held") {
              // Escrow already confirmed on a previous call — self-heal the listing status if
              // it's still stuck at pending_escrow (this was a real bug: earlier versions of
              // this function never promoted the listing itself), otherwise nothing to do.
              if (listing.status == "pending_escrow") {
                let healedListing : NftListing = { id = listing.id; listingType = listing.listingType; name = listing.name; description = listing.description; rarity = listing.rarity; ticketCost = listing.ticketCost; imageUrl = listing.imageUrl; creator = listing.creator; tier = listing.tier; status = "live"; feePaid = listing.feePaid; showroomFeePaid = listing.showroomFeePaid; txId = listing.txId; createdAt = listing.createdAt; sourceCanisterId = listing.sourceCanisterId; sourceTokenId = listing.sourceTokenId; sourceTokenKey = listing.sourceTokenKey; collectionName = listing.collectionName; };
                nftListings.put(listingId, healedListing);
                return #ok("✅ Listing status repaired — DIP-721 NFT was already escrowed.");
              };
              return #err("NFT already escrowed");
            };
          };
          case null {};
        };
        try {
          let dip721 = getDip721Actor(canisterId);
          let ownerResult = await dip721.ownerOfDip721(tokenId);
          switch (ownerResult) {
            case (#Ok(owner)) {
              let self = Principal.fromActor(ArcadeBackend);
              if (not Principal.equal(owner, self)) return #err("NFT not yet transferred to arcade. Owner: " # Principal.toText(owner) # ". Transfer to: " # Principal.toText(self));
              let escrow : EscrowedNft = { listingId; canisterId; tokenId = Nat64.toText(tokenId); standard = "dip721"; depositor = listing.creator; depositedAt = Time.now(); status = "held"; redeemedBy = null; redeemedAt = null; };
              escrows.put(listingId, escrow);
              let updatedListing : NftListing = { id = listing.id; listingType = listing.listingType; name = listing.name; description = listing.description; rarity = listing.rarity; ticketCost = listing.ticketCost; imageUrl = listing.imageUrl; creator = listing.creator; tier = listing.tier; status = if (listing.status == "pending_escrow") "live" else listing.status; feePaid = listing.feePaid; showroomFeePaid = listing.showroomFeePaid; txId = listing.txId; createdAt = listing.createdAt; sourceCanisterId = listing.sourceCanisterId; sourceTokenId = listing.sourceTokenId; sourceTokenKey = listing.sourceTokenKey; collectionName = listing.collectionName; };
              nftListings.put(listingId, updatedListing);
              #ok("✅ DIP-721 NFT escrowed! " # listing.name # " is now available for purchase.");
            };
            case (#Err(_)) { #err("Token not found on DIP-721 canister") };
          };
        } catch (e) { #err("DIP-721 verification failed: " # Error.message(e)); };
      };
    };
  };

  /// Confirm ICRC-7 NFT escrow — verifies icrc7_owner_of returns this canister
  public shared(msg) func confirmIcrc7Escrow(listingId : Text, canisterId : Text, tokenId : Nat) : async Result.Result<Text, Text> {
    let caller = msg.caller;
    if (Principal.isAnonymous(caller)) return #err("Must be authenticated");
    hydrateRuntimeStateIfNeeded();
    switch (nftListings.get(listingId)) {
      case null { return #err("Listing not found: " # listingId) };
      case (?listing) {
        if (not Principal.equal(listing.creator, caller) and not isAdmin(caller)) return #err("Not the listing owner");
        switch (escrows.get(listingId)) {
          case (?existing) {
            if (existing.status == "held") {
              // Escrow already confirmed on a previous call — self-heal the listing status if
              // it's still stuck at pending_escrow (this was a real bug: earlier versions of
              // this function never promoted the listing itself), otherwise nothing to do.
              if (listing.status == "pending_escrow") {
                let healedListing : NftListing = { id = listing.id; listingType = listing.listingType; name = listing.name; description = listing.description; rarity = listing.rarity; ticketCost = listing.ticketCost; imageUrl = listing.imageUrl; creator = listing.creator; tier = listing.tier; status = "live"; feePaid = listing.feePaid; showroomFeePaid = listing.showroomFeePaid; txId = listing.txId; createdAt = listing.createdAt; sourceCanisterId = listing.sourceCanisterId; sourceTokenId = listing.sourceTokenId; sourceTokenKey = listing.sourceTokenKey; collectionName = listing.collectionName; };
                nftListings.put(listingId, healedListing);
                return #ok("✅ Listing status repaired — ICRC-7 NFT was already escrowed.");
              };
              return #err("NFT already escrowed");
            };
          };
          case null {};
        };
        try {
          let icrc7 = getDynamicIcrc7Actor(canisterId);
          let ownerResult = await icrc7.icrc7_owner_of(tokenId);
          switch (ownerResult) {
            case (#Ok(account)) {
              let self = Principal.fromActor(ArcadeBackend);
              if (not Principal.equal(account.owner, self)) return #err("NFT not yet transferred to arcade. Owner: " # Principal.toText(account.owner) # ". Transfer to: " # Principal.toText(self));
              let escrow : EscrowedNft = { listingId; canisterId; tokenId = Nat.toText(tokenId); standard = "icrc7"; depositor = listing.creator; depositedAt = Time.now(); status = "held"; redeemedBy = null; redeemedAt = null; };
              escrows.put(listingId, escrow);
              let updatedListing : NftListing = { id = listing.id; listingType = listing.listingType; name = listing.name; description = listing.description; rarity = listing.rarity; ticketCost = listing.ticketCost; imageUrl = listing.imageUrl; creator = listing.creator; tier = listing.tier; status = if (listing.status == "pending_escrow") "live" else listing.status; feePaid = listing.feePaid; showroomFeePaid = listing.showroomFeePaid; txId = listing.txId; createdAt = listing.createdAt; sourceCanisterId = listing.sourceCanisterId; sourceTokenId = listing.sourceTokenId; sourceTokenKey = listing.sourceTokenKey; collectionName = listing.collectionName; };
              nftListings.put(listingId, updatedListing);
              #ok("✅ ICRC-7 NFT escrowed! " # listing.name # " is now available for purchase.");
            };
            case (#Err(_)) { #err("Token not found on ICRC-7 canister") };
          };
        } catch (e) { #err("ICRC-7 verification failed: " # Error.message(e)); };
      };
    };
  };

  /// Redeem a user-listed NFT by spending tickets.
  /// Transfers the escrowed NFT first; only after transfer success are buyer Tickets burned
  /// and seller claimable ICP credited at the fixed 1 ICP = 1,000 Tickets rate.
  public shared(msg) func redeemUserNft(listingId : Text) : async Result.Result<Text, Text> {
    assert (not isBannedNow(msg.caller)); // banned: only withdrawals, claims and listing allowed
    let caller = msg.caller;
    if (Principal.isAnonymous(caller)) return #err("Must be authenticated via Internet Identity");
    hydrateRuntimeStateIfNeeded();

    // Get listing
    switch (nftListings.get(listingId)) {
      case null { return #err("Listing not found") };
      case (?listing) {
        if (listing.status != "live") return #err("Listing is not active");

        if (listing.listingType == "mint") {
          let balance = getTicketBalance(caller);
          let cost = listing.ticketCost;
          if (balance < cost) {
            return #err("Not enough tickets. Need " # Nat.toText(cost) # " but have " # Nat.toText(balance));
          };
          // Reserve BEFORE the await (session #3 fix): debit tickets and lock the listing so a concurrent
          // redeem can't reuse a stale balance or grab the same listing; refunded/unlocked if the transfer fails.
          tickets.put(caller, balance - cost);
          nftListings.put(listingId, { listing with status = "redeeming" });
          let mintTransferOk : Result.Result<Text, Text> = try {
            let r = await nftCanister().icrc7_transfer({
              to = { owner = caller; subaccount = null };
              spender_subaccount = null;
              from = null;
              memo = null;
              is_atomic = null;
              token_ids = [listing.sourceTokenId];
              created_at_time = null;
            });
            switch (r) { case (#Ok(_)) { #ok("ok") }; case (#Err(_)) { #err("ICRC-7 transfer failed") }; };
          } catch (e) { #err("ICRC-7 call failed: " # Error.message(e)) };
          switch (mintTransferOk) {
            case (#err(errMsg)) {
              tickets.put(caller, getTicketBalance(caller) + cost);
              nftListings.put(listingId, { listing with status = "live" });
              return #err(errMsg);
            };
            case (#ok(_)) {
              let updList : NftListing = { id = listing.id; listingType = listing.listingType; name = listing.name; description = listing.description; rarity = listing.rarity; ticketCost = listing.ticketCost; imageUrl = listing.imageUrl; creator = listing.creator; tier = listing.tier; status = "sold"; feePaid = listing.feePaid; showroomFeePaid = listing.showroomFeePaid; txId = listing.txId; createdAt = listing.createdAt; sourceCanisterId = listing.sourceCanisterId; sourceTokenId = listing.sourceTokenId; sourceTokenKey = listing.sourceTokenKey; collectionName = listing.collectionName; };
              nftListings.put(listingId, updList);
              logRevenue("official-nft-redeem", ticketCostToSellerPayoutE8s(cost), caller, 7);
              setOfficialOwner(listing.sourceTokenId, ?caller); // abilities follow the new owner
              // Prize Booth split for Official NFTs: arcade 80%, DAO 20% (of the spent tickets' ICP backing)
              let offE8s = ticketCostToSellerPayoutE8s(cost);
              let offDaoE8s = offE8s * 20 / 100;
              daoTreasuryE8s += offDaoE8s;
              daoInOfficialNftE8s += offDaoE8s;
              prizeBoothArcadeShareE8s += offE8s - offDaoE8s;
              addMxp(caller, 21);
              return #ok("🎉 NFT redeemed! " # listing.name # " transferred to your wallet.");
            };
          };
        };

        // Get escrow
        switch (escrows.get(listingId)) {
          case null { return #err("NFT not in escrow — not available for purchase yet") };
          case (?escrow) {
            if (escrow.status != "held") return #err("NFT escrow status: " # escrow.status # " — not available");

            // Check ticket balance
            let balance = getTicketBalance(caller);
            let cost = listing.ticketCost;
            if (balance < cost) {
              return #err("Not enough tickets. Need " # Nat.toText(cost) # " but have " # Nat.toText(balance));
            };

            // Reserve BEFORE the await (session #3 fix): debit tickets, lock escrow + listing; undone on failure.
            tickets.put(caller, balance - cost);
            escrows.put(listingId, { escrow with status = "redeeming" });
            nftListings.put(listingId, { listing with status = "redeeming" });
            // Transfer NFT based on standard
            let transferOk : Result.Result<Text, Text> = if (escrow.standard == "dip721") {
              try {
                let dip721 = getDip721Actor(escrow.canisterId);
                let self = Principal.fromActor(ArcadeBackend);
                // DIP-721 uses Nat64 token IDs
                let tidNat : Nat = switch (Nat.fromText(escrow.tokenId)) { case (?n) n; case null 0; };
                let tid : Nat64 = Nat64.fromNat(tidNat);
                let r = await dip721.transferFromDip721(self, caller, tid);
                switch (r) { case (#Ok(_)) { #ok("ok") }; case (#Err(e)) { let m = switch (e) { case (#UnauthorizedOwner) { "UnauthorizedOwner" }; case (#UnauthorizedOperator) { "UnauthorizedOperator" }; case (#OwnerNotFound) { "OwnerNotFound" }; case (#TokenNotFound) { "TokenNotFound" }; case (#ExistedNFT) { "ExistedNFT" }; case (#SelfTransfer) { "SelfTransfer" }; case (#Other(msg2)) { msg2 }; }; #err("DIP-721: " # m) }; };
              } catch (e) { #err("DIP-721 call failed: " # Error.message(e)) };
            } else if (escrow.standard == "icrc7") {
              try {
                let icrc7 = getDynamicIcrc7Actor(escrow.canisterId);
                let tid : Nat = switch (Nat.fromText(escrow.tokenId)) { case (?n) n; case null 0; };
                let r = await icrc7.icrc7_transfer({ to = { owner = caller; subaccount = null }; spender_subaccount = null; from = null; memo = null; is_atomic = null; token_ids = [tid]; created_at_time = null; });
                switch (r) { case (#Ok(_)) { #ok("ok") }; case (#Err(_)) { #err("ICRC-7 transfer failed") }; };
              } catch (e) { #err("ICRC-7 call failed: " # Error.message(e)) };
            } else {
              #err("Unknown NFT standard: " # escrow.standard);
            };

            switch (transferOk) {
              case (#ok(_)) {
                if (isOfficialNftCanister(escrow.canisterId)) { switch (Nat.fromText(escrow.tokenId)) { case (?t) { setOfficialOwner(t, ?caller) }; case null {} } };
                let grossE8s = ticketCostToSellerPayoutE8s(cost);
                // Prize Booth split for player-listed NFTs: seller 97%, arcade 1.5%, DAO 1.5%
                let daoCutE8s = grossE8s * 15 / 1000;
                let arcadeCutE8s = grossE8s * 15 / 1000;
                let sellerPayoutE8s = grossE8s - daoCutE8s - arcadeCutE8s;
                daoTreasuryE8s += daoCutE8s;
                daoInPlayerNftE8s += daoCutE8s;
                prizeBoothArcadeShareE8s += arcadeCutE8s;
                // Buyer tickets were already debited before the transfer; credit seller only after success.
                ignore creditNftSellerEarnings(listing.creator, sellerPayoutE8s);
                // Update escrow
                let updEsc : EscrowedNft = { listingId = escrow.listingId; canisterId = escrow.canisterId; tokenId = escrow.tokenId; standard = escrow.standard; depositor = escrow.depositor; depositedAt = escrow.depositedAt; status = "redeemed"; redeemedBy = ?caller; redeemedAt = ?Time.now(); };
                escrows.put(listingId, updEsc);
                // Update listing
                let updList : NftListing = { id = listing.id; listingType = listing.listingType; name = listing.name; description = listing.description; rarity = listing.rarity; ticketCost = listing.ticketCost; imageUrl = listing.imageUrl; creator = listing.creator; tier = listing.tier; status = "sold"; feePaid = listing.feePaid; showroomFeePaid = listing.showroomFeePaid; txId = listing.txId; createdAt = listing.createdAt; sourceCanisterId = listing.sourceCanisterId; sourceTokenId = listing.sourceTokenId; sourceTokenKey = listing.sourceTokenKey; collectionName = listing.collectionName; };
                nftListings.put(listingId, updList);
                // Seller payout is claimable ICP in the separate NFT seller earnings bucket.
                // Do not write game creator royalties here.
                logRevenue("nft-redeem", sellerPayoutE8s, caller, 7);
                addMxp(caller, 21);
                addMxp(listing.creator, 12);
                #ok("🎉 NFT redeemed! " # listing.name # " transferred to your wallet. Seller credited " # Nat.toText(sellerPayoutE8s) # " e8s claimable ICP.");
              };
              case (#err(errMsg)) {
                tickets.put(caller, getTicketBalance(caller) + cost);
                escrows.put(listingId, { escrow with status = "held" });
                nftListings.put(listingId, { listing with status = "live" });
                #err(errMsg);
              };
            };
          };
        };
      };
    };
  };

  /// Return an escrowed NFT to the player who listed it (delisting). Allowed for that player or an admin.
  public shared(msg) func returnEscrowNft(listingId : Text) : async Result.Result<Text, Text> {
    assert (not isBannedNow(msg.caller)); // banned: only withdrawals, claims and listing allowed
    hydrateRuntimeStateIfNeeded();

    switch (escrows.get(listingId)) {
      case null { return #err("No escrow found for listing: " # listingId) };
      case (?escrow) {
        if (escrow.status != "held") return #err("Escrow status is " # escrow.status # " — cannot return");
        if (not isAdmin(msg.caller) and not Principal.equal(escrow.depositor, msg.caller)) return #err("Only the player who listed this NFT (or an admin) can delist it");

        let self = Principal.fromActor(ArcadeBackend);
        let returnOk : Result.Result<Text, Text> = if (escrow.standard == "dip721") {
          try {
            let dip721 = getDip721Actor(escrow.canisterId);
            let tidNat2 : Nat = switch (Nat.fromText(escrow.tokenId)) { case (?n) n; case null 0; };
            let tid : Nat64 = Nat64.fromNat(tidNat2);
            let r = await dip721.transferFromDip721(self, escrow.depositor, tid);
            switch (r) { case (#Ok(_)) { #ok("ok") }; case (#Err(_)) { #err("DIP-721 return failed") }; };
          } catch (e) { #err("DIP-721 call: " # Error.message(e)) };
        } else if (escrow.standard == "icrc7") {
          try {
            let icrc7 = getDynamicIcrc7Actor(escrow.canisterId);
            let tid : Nat = switch (Nat.fromText(escrow.tokenId)) { case (?n) n; case null 0; };
            let r = await icrc7.icrc7_transfer({ to = { owner = escrow.depositor; subaccount = null }; spender_subaccount = null; from = null; memo = null; is_atomic = null; token_ids = [tid]; created_at_time = null; });
            switch (r) { case (#Ok(_)) { #ok("ok") }; case (#Err(_)) { #err("ICRC-7 return failed") }; };
          } catch (e) { #err("ICRC-7 call: " # Error.message(e)) };
        } else { #err("Unknown standard: " # escrow.standard) };

        switch (returnOk) {
          case (#ok(_)) {
            if (isOfficialNftCanister(escrow.canisterId)) { switch (Nat.fromText(escrow.tokenId)) { case (?t) { setOfficialOwner(t, ?escrow.depositor) }; case null {} } };
            let updated : EscrowedNft = { listingId = escrow.listingId; canisterId = escrow.canisterId; tokenId = escrow.tokenId; standard = escrow.standard; depositor = escrow.depositor; depositedAt = escrow.depositedAt; status = "returned"; redeemedBy = null; redeemedAt = ?Time.now(); };
            escrows.put(listingId, updated);
            // Delisting completes in one step: the listing leaves the Prize Booth as the NFT goes home.
            switch (nftListings.get(listingId)) { case (?l) { nftListings.put(listingId, { l with status = "removed" }) }; case null {} };
            #ok("NFT returned to " # Principal.toText(escrow.depositor));
          };
          case (#err(msg2)) { #err(msg2) };
        };
      };
    };
  };

  /// Get escrow status for a listing
  public query func getEscrowStatus(listingId : Text) : async ?EscrowedNft {
    if (runtimeStateHydrated) {
      escrows.get(listingId);
    } else {
      findTextValue<EscrowedNft>(escrowEntries, listingId);
    };
  };

  /// Get all active escrows (admin)
  public query func getAllEscrows() : async [(Text, EscrowedNft)] {
    if (runtimeStateHydrated) {
      Iter.toArray(escrows.entries());
    } else {
      escrowEntries;
    };
  };

  // ============================================
  // === REVENUE & STATS ===
  // ============================================

  /// Get revenue log (admin only)
  public query func getRevenueLog() : async [RevenueEvent] {
    revenueLogEntries;
  };

  /// Get total revenue collected (in e8s)
  public query func getTotalRevenue() : async Nat {
    totalRevenueE8s;
  };

  /// Get revenue summary by type
  public query func getRevenueSummary() : async [(Text, Nat)] {
    let types = ["nft-list", "nft-mint", "nft-showroom", "game-backroom", "game-showroom", "token-purchase", "nft-redeem", "blackhole-submit"];
    Array.map<Text, (Text, Nat)>(types, func(t) {
      var total : Nat = 0;
      for (e in revenueLogEntries.vals()) {
        if (e.eventType == t) { total += e.amount };
      };
      (t, total);
    });
  };

  // ============================================
  // === EXISTING V1 FUNCTIONS (preserved) ===
  // ============================================

  /// Credit tickets to a player (admin only)
  public shared(msg) func addTickets(player : Principal, amount : Nat) : async Result.Result<Nat, Text> {
    assert (not isBannedNow(msg.caller)); // banned: only withdrawals, claims and listing allowed
    if (not ALLOW_TEST_MINTING) return #err("Test minting is disabled on this network");
    if (not isAdmin(msg.caller)) return #err("Not authorized");
    hydrateRuntimeStateIfNeeded();
    let current = getTicketBalance(player);
    let newBal = current + amount;
    tickets.put(player, newBal);
    #ok(newBal);
  };

  /// Set tickets to exact amount (admin only) — for resets
  public shared(msg) func adminSetTickets(player : Principal, amount : Nat) : async Result.Result<Nat, Text> {
    assert (not isBannedNow(msg.caller)); // banned: only withdrawals, claims and listing allowed
    if (not isAdmin(msg.caller)) return #err("Not authorized");
    hydrateRuntimeStateIfNeeded();
    if (not ALLOW_TEST_MINTING and amount > getTicketBalance(player)) return #err("Raising ticket balances is disabled on this network (reductions still allowed)");
    tickets.put(player, amount);
    #ok(amount);
  };

  /// Batch credit tickets (admin only)
  public shared(msg) func batchAddTickets(entries : [(Principal, Nat)]) : async Result.Result<Nat, Text> {
    assert (not isBannedNow(msg.caller)); // banned: only withdrawals, claims and listing allowed
    if (not ALLOW_TEST_MINTING) return #err("Test minting is disabled on this network");
    if (not isAdmin(msg.caller)) return #err("Not authorized");
    hydrateRuntimeStateIfNeeded();
    var count = 0;
    for ((player, amount) in entries.vals()) {
      let current = getTicketBalance(player);
      tickets.put(player, current + amount);
      count += 1;
    };
    #ok(count);
  };

  /// Set ticket cost for an NFT (admin only)
  public shared(msg) func setNftCost(tokenId : TokenId, cost : Nat) : async Result.Result<(), Text> {
    assert (not isBannedNow(msg.caller)); // banned: only withdrawals, claims and listing allowed
    if (not isAdmin(msg.caller)) return #err("Not authorized");
    hydrateRuntimeStateIfNeeded();
    costs.put(tokenId, cost);
    #ok();
  };

  /// Batch set NFT costs (admin only)
  public shared(msg) func batchSetNftCosts(entries : [(TokenId, Nat)]) : async Result.Result<(), Text> {
    assert (not isBannedNow(msg.caller)); // banned: only withdrawals, claims and listing allowed
    if (not isAdmin(msg.caller)) return #err("Not authorized");
    hydrateRuntimeStateIfNeeded();
    for ((id, cost) in entries.vals()) {
      costs.put(id, cost);
    };
    #ok();
  };

  /// Set default ticket cost (admin only)
  public shared(msg) func setDefaultCost(cost : Nat) : async Result.Result<(), Text> {
    assert (not isBannedNow(msg.caller)); // banned: only withdrawals, claims and listing allowed
    if (not isAdmin(msg.caller)) return #err("Not authorized");
    defaultCost := cost;
    #ok();
  };

  /// Get ticket balance for a player
  public query func getTickets(player : Principal) : async Nat {
    getTicketBalance(player);
  };

  /// Get NFT ticket cost
  public query func getNftCost(tokenId : TokenId) : async Nat {
    getCost(tokenId);
  };

  /// Get all NFT costs
  public query func getAllNftCosts() : async [(TokenId, Nat)] {
    if (runtimeStateHydrated) {
      Iter.toArray(costs.entries());
    } else {
      costEntries;
    };
  };

  /// Get redemption history
  public query func getRedemptions() : async [(Principal, TokenId, Int)] {
    redemptionLog;
  };

  /// Get all ticket balances (admin view)
  public query func getAllTickets() : async [(Principal, Nat)] {
    if (runtimeStateHydrated) {
      Iter.toArray(tickets.entries());
    } else {
      ticketEntries;
    };
  };

  /// Get all token balances
  public query func getAllTokens() : async [(Principal, Nat)] {
    if (runtimeStateHydrated) {
      Iter.toArray(tokens.entries());
    } else {
      tokenEntries;
    };
  };

  /// Get total circulation stats (admin dashboard)
  public query func getTotalCirculation() : async { totalTickets : Nat; totalTokens : Nat; totalPlayers : Nat } {
    var tTickets : Nat = 0;
    var tTokens : Nat = 0;
    var players : Nat = 0;
    let ticketSource = if (runtimeStateHydrated) { Iter.toArray(tickets.entries()) } else { ticketEntries };
    let tokenSource = if (runtimeStateHydrated) { Iter.toArray(tokens.entries()) } else { tokenEntries };
    for ((_, bal) in ticketSource.vals()) { tTickets += bal; };
    for ((_, bal) in tokenSource.vals()) { tTokens += bal; };
    let seen = HashMap.HashMap<Principal, Bool>(16, Principal.equal, Principal.hash);
    for ((p, _) in ticketSource.vals()) { seen.put(p, true); };
    for ((p, _) in tokenSource.vals()) { seen.put(p, true); };
    players := seen.size();
    { totalTickets = tTickets; totalTokens = tTokens; totalPlayers = players };
  };

  /// Redeem an NFT by spending tickets
  public shared(msg) func redeem(tokenId : TokenId) : async Result.Result<Text, Text> {
    assert (not isBannedNow(msg.caller)); // banned: only withdrawals, claims and listing allowed
    if (true) return #err("Retired: redeem Official NFTs through the Prize Booth");
    let caller = msg.caller;
    if (Principal.isAnonymous(caller)) return #err("Must be authenticated via Internet Identity");
    hydrateRuntimeStateIfNeeded();

    let balance = getTicketBalance(caller);
    let cost = getCost(tokenId);
    if (balance < cost) {
      return #err("Not enough tickets. Need " # Nat.toText(cost) # " but have " # Nat.toText(balance));
    };

    // Debit BEFORE the await (session #3 fix); refunded below if the transfer fails.
    tickets.put(caller, balance - cost);
    try {
      let result = await nftCanister().icrc7_transfer({
        to = { owner = caller; subaccount = null };
        spender_subaccount = null;
        from = null;
        memo = null;
        is_atomic = null;
        token_ids = [tokenId];
        created_at_time = null;
      });

      switch (result) {
        case (#Ok(_)) {
          let log = Buffer.fromArray<(Principal, TokenId, Int)>(redemptionLog);
          log.add((caller, tokenId, Time.now()));
          redemptionLog := Buffer.toArray(log);
          #ok("NFT #" # Nat.toText(tokenId) # " transferred to your wallet!");
        };
        case (#Err(e)) {
          tickets.put(caller, getTicketBalance(caller) + cost);
          #err("Transfer failed. The NFT may not be available.");
        };
      };
    } catch (e) {
      tickets.put(caller, getTicketBalance(caller) + cost);
      #err("Transfer call failed: " # Error.message(e));
    };
  };

  // === ICP WITHDRAW ===
  // ICP Ledger interface for transfers
  type Icrc1TransferArg = {
    to : { owner : Principal; subaccount : ?Blob };
    fee : ?Nat;
    memo : ?Blob;
    from_subaccount : ?Blob;
    created_at_time : ?Nat64;
    amount : Nat;
  };
  type Icrc1TransferResult = {
    #Ok : Nat;
    #Err : {
      #BadFee : { expected_fee : Nat };
      #BadBurn : { min_burn_amount : Nat };
      #InsufficientFunds : { balance : Nat };
      #TooOld;
      #CreatedInFuture : { ledger_time : Nat64 };
      #Duplicate : { duplicate_of : Nat };
      #TemporarilyUnavailable;
      #GenericError : { error_code : Nat; message : Text };
    };
  };
  transient let ICP_LEDGER : actor { icrc1_transfer : shared Icrc1TransferArg -> async Icrc1TransferResult } = actor("ryjl3-tyaaa-aaaaa-aaaba-cai");

  type ClassicLedgerTransferResult = {
    #Ok : Nat64;
    #Err : {
      #BadFee : { expected_fee : { e8s : Nat64 } };
      #InsufficientFunds : { balance : { e8s : Nat64 } };
      #TxTooOld : { allowed_window_nanos : Nat64 };
      #TxCreatedInFuture;
      #TxDuplicate : { duplicate_of : Nat64 };
    };
  };
  transient let ICP_LEDGER_CLASSIC : actor {
    transfer : shared {
      to : Blob;
      fee : { e8s : Nat64 };
      memo : Nat64;
      from_subaccount : ?Blob;
      created_at_time : ?{ timestamp_nanos : Nat64 };
      amount : { e8s : Nat64 };
    } -> async ClassicLedgerTransferResult;
  } = actor("ryjl3-tyaaa-aaaaa-aaaba-cai");

  func icpTransferErrorText(prefix : Text, e : {
    #BadFee : { expected_fee : Nat };
    #BadBurn : { min_burn_amount : Nat };
    #InsufficientFunds : { balance : Nat };
    #TooOld;
    #CreatedInFuture : { ledger_time : Nat64 };
    #Duplicate : { duplicate_of : Nat };
    #TemporarilyUnavailable;
    #GenericError : { error_code : Nat; message : Text };
  }) : Text {
    switch (e) {
      case (#InsufficientFunds(f)) { prefix # " insufficient funds: " # Nat.toText(f.balance) # " e8s available" };
      case (#BadFee(f)) { prefix # " bad fee: expected " # Nat.toText(f.expected_fee) # " e8s" };
      case (#TooOld) { prefix # " rejected as too old; please retry" };
      case (#CreatedInFuture(_)) { prefix # " rejected timestamp as created in future; please retry" };
      case (#Duplicate(d)) { prefix # " duplicate transfer: block " # Nat.toText(d.duplicate_of) };
      case (#TemporarilyUnavailable) { prefix # " ledger temporarily unavailable; please retry" };
      case (#GenericError(g)) { prefix # " ledger error " # Nat.toText(g.error_code) # ": " # g.message };
      case (#BadBurn(_)) { prefix # " rejected transfer amount" };
    }
  };

  func adminWithdrawOperatingTreasuryImpl(destination : Account, amountE8s : Nat) : async Result.Result<Nat, Text> {
    if (operatingTreasuryWithdrawalInFlight) return #err("Operating Treasury withdrawal already in progress");
    if (amountE8s <= ICP_LEDGER_FEE_E8S) {
      return #err("Operating Treasury withdrawal amount must exceed ledger fee dust: " # Nat.toText(ICP_LEDGER_FEE_E8S) # " e8s");
    };

    let selfPrincipal = Principal.fromActor(ArcadeBackend);
    let requiredE8s = amountE8s + ICP_LEDGER_FEE_E8S;
    operatingTreasuryWithdrawalInFlight := true;
    try {
      let operatingBalanceE8s = await ICP_LEDGER_ICRC1.icrc1_balance_of({ owner = selfPrincipal; subaccount = ?OPERATING_TREASURY_SUBACCOUNT });
      if (operatingBalanceE8s < requiredE8s) {
        operatingTreasuryWithdrawalInFlight := false;
        return #err(
          "Operating Treasury has insufficient funds: " # Nat.toText(operatingBalanceE8s) #
          " e8s available; need " # Nat.toText(requiredE8s) # " e8s including fee"
        );
      };

      let result = await ICP_LEDGER.icrc1_transfer({
        to = destination;
        fee = null;
        memo = null;
        from_subaccount = ?OPERATING_TREASURY_SUBACCOUNT;
        created_at_time = ?ledgerNow();
        amount = amountE8s;
      });
      operatingTreasuryWithdrawalInFlight := false;
      switch (result) {
        case (#Ok(blockIndex)) { #ok(blockIndex) };
        case (#Err(e)) { #err(icpTransferErrorText("Operating Treasury withdrawal", e)) };
      }
    } catch (e) {
      operatingTreasuryWithdrawalInFlight := false;
      #err("Operating Treasury withdrawal transfer error: " # Error.message(e))
    }
  };

  /// Admin-only withdrawal from the separated Operating Treasury subaccount.
  /// Amount is the net ICP e8s sent to destination; the operating subaccount must also cover the ledger fee.
  public shared(msg) func adminWithdrawOperatingTreasury(destination : Account, amountE8s : Nat) : async Result.Result<Nat, Text> {
    assert (not isBannedNow(msg.caller)); // banned: only withdrawals, claims and listing allowed
    if (not isAdmin(msg.caller)) return #err("Admin only");
    await adminWithdrawOperatingTreasuryImpl(destination, amountE8s)
  };

  func adminWithdrawBlackholeTreasuryImpl(destination : Account, amountE8s : Nat) : async Result.Result<Nat, Text> {
    if (blackholeTreasuryWithdrawalInFlight) return #err("Blackhole Treasury withdrawal already in progress");
    if (amountE8s <= ICP_LEDGER_FEE_E8S) {
      return #err("Blackhole Treasury withdrawal amount must exceed ledger fee dust: " # Nat.toText(ICP_LEDGER_FEE_E8S) # " e8s");
    };

    let selfPrincipal = Principal.fromActor(ArcadeBackend);
    let requiredE8s = amountE8s + ICP_LEDGER_FEE_E8S;
    blackholeTreasuryWithdrawalInFlight := true;
    try {
      let blackholeBalanceE8s = await ICP_LEDGER_ICRC1.icrc1_balance_of({ owner = selfPrincipal; subaccount = ?BLACKHOLE_TREASURY_SUBACCOUNT });
      if (blackholeBalanceE8s < requiredE8s) {
        blackholeTreasuryWithdrawalInFlight := false;
        return #err(
          "Blackhole Treasury has insufficient funds: " # Nat.toText(blackholeBalanceE8s) #
          " e8s available; need " # Nat.toText(requiredE8s) # " e8s including fee"
        );
      };

      let result = await ICP_LEDGER.icrc1_transfer({
        to = destination;
        fee = null;
        memo = null;
        from_subaccount = ?BLACKHOLE_TREASURY_SUBACCOUNT;
        created_at_time = ?ledgerNow();
        amount = amountE8s;
      });
      blackholeTreasuryWithdrawalInFlight := false;
      switch (result) {
        case (#Ok(blockIndex)) { #ok(blockIndex) };
        case (#Err(e)) { #err(icpTransferErrorText("Blackhole Treasury withdrawal", e)) };
      }
    } catch (e) {
      blackholeTreasuryWithdrawalInFlight := false;
      #err("Blackhole Treasury withdrawal transfer error: " # Error.message(e))
    }
  };

  /// Admin-only withdrawal from the dedicated Blackhole Treasury subaccount.
  /// Amount is the net ICP e8s sent to destination; the subaccount must also cover the ledger fee.
  public shared(msg) func adminWithdrawBlackholeTreasury(destination : Account, amountE8s : Nat) : async Result.Result<Nat, Text> {
    assert (not isBannedNow(msg.caller)); // banned: only withdrawals, claims and listing allowed
    if (not isAdmin(msg.caller)) return #err("Admin only");
    await adminWithdrawBlackholeTreasuryImpl(destination, amountE8s)
  };

  /// Read-only: current live balance of the dedicated Blackhole Treasury subaccount (admin only).
  public shared(msg) func getBlackholeTreasuryBalance() : async Result.Result<Nat, Text> {
    assert (not isBannedNow(msg.caller)); // banned: only withdrawals, claims and listing allowed
    if (not isAdmin(msg.caller)) return #err("Admin only");
    let selfPrincipal = Principal.fromActor(ArcadeBackend);
    let balanceE8s = await ICP_LEDGER_ICRC1.icrc1_balance_of({ owner = selfPrincipal; subaccount = ?BLACKHOLE_TREASURY_SUBACCOUNT });
    #ok(balanceE8s)
  };

  /// Admin-only withdrawal from the separated Operating Treasury subaccount to a raw ICP ledger account ID.
  /// Amount is the net ICP e8s sent; the operating subaccount must also cover the classic ledger fee.
  public shared(msg) func adminWithdrawOperatingTreasuryToAccountId(toAccountHex : Text, amountE8s : Nat) : async Result.Result<Nat, Text> {
    assert (not isBannedNow(msg.caller)); // banned: only withdrawals, claims and listing allowed
    if (not isAdmin(msg.caller)) return #err("Admin only");
    if (operatingTreasuryWithdrawalInFlight) return #err("Operating Treasury withdrawal already in progress");
    if (amountE8s == 0) return #err("Operating Treasury withdrawal amount must be greater than zero");

    let destinationBlob = switch (hexToBlob(toAccountHex)) {
      case (?blob) { blob };
      case null { return #err("Destination account ID must be exactly 64 hexadecimal characters") };
    };

    let selfPrincipal = Principal.fromActor(ArcadeBackend);
    let requiredE8s = amountE8s + ICP_LEDGER_FEE_E8S;
    operatingTreasuryWithdrawalInFlight := true;
    try {
      let operatingBalanceE8s = await ICP_LEDGER_ICRC1.icrc1_balance_of({ owner = selfPrincipal; subaccount = ?OPERATING_TREASURY_SUBACCOUNT });
      if (operatingBalanceE8s < requiredE8s) {
        operatingTreasuryWithdrawalInFlight := false;
        return #err(
          "Operating Treasury has insufficient funds: " # Nat.toText(operatingBalanceE8s) #
          " e8s available; need " # Nat.toText(requiredE8s) # " e8s including fee"
        );
      };

      let result = await ICP_LEDGER_CLASSIC.transfer({
        to = destinationBlob;
        fee = { e8s = 10_000 : Nat64 };
        memo = 0 : Nat64;
        from_subaccount = ?OPERATING_TREASURY_SUBACCOUNT;
        created_at_time = ?{ timestamp_nanos = ledgerNow() };
        amount = { e8s = Nat64.fromNat(amountE8s) };
      });
      operatingTreasuryWithdrawalInFlight := false;
      switch (result) {
        case (#Ok(blockIndex)) { #ok(Nat64.toNat(blockIndex)) };
        case (#Err(e)) {
          switch (e) {
            case (#InsufficientFunds(f)) { #err("Operating Treasury withdrawal insufficient funds: " # Nat64.toText(f.balance.e8s) # " e8s available") };
            case (#BadFee(f)) { #err("Operating Treasury withdrawal bad fee: expected " # Nat64.toText(f.expected_fee.e8s) # " e8s") };
            case (#TxTooOld(_)) { #err("Operating Treasury withdrawal rejected as too old; please retry") };
            case (#TxCreatedInFuture) { #err("Operating Treasury withdrawal rejected timestamp as created in future; please retry") };
            case (#TxDuplicate(d)) { #err("Operating Treasury withdrawal duplicate transfer: block " # Nat64.toText(d.duplicate_of)) };
          }
        };
      }
    } catch (e) {
      operatingTreasuryWithdrawalInFlight := false;
      #err("Operating Treasury withdrawal transfer error: " # Error.message(e))
    }
  };

  /// Legacy admin-panel wrapper: withdraw Operating Treasury ICP to a principal main account.
  public shared(msg) func adminWithdrawTreasury(toPrincipal : Principal, amountE8s : Nat) : async Result.Result<Nat, Text> {
    assert (not isBannedNow(msg.caller)); // banned: only withdrawals, claims and listing allowed
    if (not isAdmin(msg.caller)) return #err("Admin only");
    await adminWithdrawOperatingTreasuryImpl({ owner = toPrincipal; subaccount = null }, amountE8s)
  };

  // Derive user's subaccount from their principal (same as frontend)
  func principalToSubaccount(p : Principal) : Blob {
    let pb = Blob.toArray(Principal.toBlob(p));
    let sub = Array.tabulate<Nat8>(32, func(i : Nat) : Nat8 {
      if (i == 0) { Nat8.fromNat(pb.size() % 256) }
      else if (i <= pb.size()) { pb[i - 1] }
      else { 0 }
    });
    Blob.fromArray(sub);
  };

  func blobToHex(blob : Blob) : Text {
    let arr = Blob.toArray(blob);
    var hex = "";
    for (b in arr.vals()) {
      let hi = Nat8.toNat(b) / 16;
      let lo = Nat8.toNat(b) % 16;
      hex := hex # hexNibble(hi) # hexNibble(lo);
    };
    hex
  };

  /// Convert ICP already deposited to this canister's per-player subaccount into arcade Tokens.
  /// Moves the converted ICP out of the player subaccount before crediting Tokens, which prevents
  /// double-conversion or later withdrawal of the same ICP.
  public shared(msg) func convertDepositToTokens(amountE8s : Nat) : async Result.Result<Nat, Text> {
    assert (not isBannedNow(msg.caller)); // banned: only withdrawals, claims and listing allowed
    let caller = msg.caller;
    if (Principal.isAnonymous(caller)) return #err("Must be authenticated");
    hydrateRuntimeStateIfNeeded();
    if (amountE8s < 1_000_000) return #err("Minimum deposit is 0.01 ICP");

    let tokenAmount = amountE8s / 1_000_000; // 0.01 ICP = 1 token
    if (tokenAmount == 0) return #err("Amount too small for any tokens");
    let convertedE8s = tokenAmount * 1_000_000;
    let ledgerFeeE8s = 10_000;
    let fromSub = principalToSubaccount(caller);
    let selfPrincipal = Principal.fromActor(ArcadeBackend);

    let bal = await ICP_LEDGER_ICRC1.icrc1_balance_of({ owner = selfPrincipal; subaccount = ?fromSub });
    if (bal < convertedE8s + ledgerFeeE8s) {
      return #err("Not enough ICP in your arcade deposit. Available " # Nat.toText(bal) # " e8s; need " # Nat.toText(convertedE8s + ledgerFeeE8s) # " e8s including ledger fee.");
    };

    try {
      let transferResult = await ICP_LEDGER.icrc1_transfer({
        to = { owner = selfPrincipal; subaccount = null };
        fee = null;
        memo = null;
        from_subaccount = ?fromSub;
        created_at_time = ?ledgerNow();
        amount = convertedE8s;
      });
      switch (transferResult) {
        case (#Ok(blockIndex)) {
          if (Option.isSome(claimedSet.get(blockIndex))) {
            return #err("Duplicate ICP ledger transfer: block " # Nat.toText(blockIndex));
          };
          claimedSet.put(blockIndex, true);
          let current = getTokenBalance(caller);
          let newBal = current + tokenAmount;
          tokens.put(caller, newBal);
          logRevenue("token-purchase", convertedE8s, caller, 6);
          #ok(newBal)
        };
        case (#Err(e)) {
          switch (e) {
            case (#InsufficientFunds(f)) { #err("Insufficient ICP in arcade deposit: " # Nat.toText(f.balance) # " e8s available") };
            case (#BadFee(f)) { #err("ICP ledger fee changed. Expected fee: " # Nat.toText(f.expected_fee) # " e8s") };
            case (#TooOld) { #err("ICP ledger rejected the transfer as too old. Please retry.") };
            case (#CreatedInFuture(_)) { #err("ICP ledger rejected the transfer timestamp. Please retry.") };
            case (#Duplicate(d)) { #err("Duplicate ICP ledger transfer: block " # Nat.toText(d.duplicate_of)) };
            case (#TemporarilyUnavailable) { #err("ICP ledger temporarily unavailable. Please retry.") };
            case (#GenericError(g)) { #err("ICP ledger error: " # g.message) };
            case (#BadBurn(_)) { #err("ICP ledger rejected the transfer amount") };
          }
        };
      }
    } catch (e) {
      #err("ICP conversion failed: " # Error.message(e))
    }
  };

  // ============ BLACKHOLE (Hole submissions) ============
  // Real implementation — was previously entirely fake: every one of these functions was declared
  // in the frontend's Candid IDL and called by the UI, but none existed anywhere in this backend,
  // so every call failed with "method not found" (IC0536), silently caught by the frontend and
  // shown as "Blackhole is waking up" / "still syncing" forever.

  func findHoleSubmission(id : Text) : ?HoleSubmission {
    for (s in holeSubmissionEntries.vals()) {
      if (s.id == id) { return ?s };
    };
    null
  };

  func activeHoleSubmissionCount(who : Principal) : Nat {
    var n = 0;
    for (s in holeSubmissionEntries.vals()) {
      if (Principal.equal(s.creator, who) and s.status == "active") { n += 1 };
    };
    n
  };

  func findHolePunishment(who : Principal) : ?HolePunishment {
    for (p in holePunishmentEntries.vals()) {
      if (Principal.equal(p.principal, who)) { return ?p };
    };
    null
  };

  // Returns the active punishment reason, if any (null once a soft punishment's window has passed).
  func holePunishmentReason(who : Principal) : ?Text {
    switch (findHolePunishment(who)) {
      case null { null };
      case (?p) {
        if (p.permanent) { ?p.reason }
        else if (Time.now() < p.until) { ?p.reason }
        else { null };
      };
    }
  };

  func findHoleVote(submissionId : Text, voter : Principal) : ?HoleVote {
    for (v in holeVoteEntries.vals()) {
      if (v.submissionId == submissionId and Principal.equal(v.voter, voter)) { return ?v };
    };
    null
  };

  // (likes, dislikes) for one submission. Low-volume linear scan — fine at current scale;
  // revisit with a real index (same pattern as the forum-thread/badge indexes built earlier)
  // if vote volume ever grows large enough for this to show up in cycle cost.
  func holeVoteCounts(id : Text) : (Nat, Nat) {
    var likes = 0; var dislikes = 0;
    for (v in holeVoteEntries.vals()) {
      if (v.submissionId == id) { if (v.isLike) { likes += 1 } else { dislikes += 1 } };
    };
    (likes, dislikes)
  };

  func findGameVote(gameId : Text, voter : Principal) : ?GameVote {
    for (v in gameVoteEntries.vals()) {
      if (v.gameId == gameId and Principal.equal(v.voter, voter)) { return ?v };
    };
    null
  };

  // Low-volume linear scan — same reasoning as holeVoteCounts above; revisit if game vote volume
  // ever grows large enough to show up in cycle cost.
  func gameVoteCounts(gameId : Text) : (Nat, Nat) {
    var likes = 0; var dislikes = 0;
    for (v in gameVoteEntries.vals()) {
      if (v.gameId == gameId) { if (v.isLike) { likes += 1 } else { dislikes += 1 } };
    };
    (likes, dislikes)
  };

  /// Toggleable: voting the same way you already voted removes your vote; voting the other way
  /// changes it. Any connected user may vote — no Voting Power requirement.
  public shared(msg) func voteGameApproval(gameId : Text, isLike : Bool) : async Result.Result<Text, Text> {
    assert (not isBannedNow(msg.caller)); // banned: only withdrawals, claims and listing allowed
    let caller = msg.caller;
    if (Principal.isAnonymous(caller)) return #err("Connect wallet to vote");
    hydrateRuntimeStateIfNeeded();
    if (Option.isNull(gameSubmissions.get(gameId))) return #err("Game not found");
    let existing = findGameVote(gameId, caller);
    let withoutMine = Array.filter<GameVote>(gameVoteEntries, func(v) {
      not (v.gameId == gameId and Principal.equal(v.voter, caller))
    });
    switch (existing) {
      case (?v) {
        if (v.isLike == isLike) {
          // Same vote again: remove it (toggle off)
          gameVoteEntries := withoutMine;
          #ok("Vote removed")
        } else {
          gameVoteEntries := Array.append<GameVote>(withoutMine, [{ gameId; voter = caller; isLike; timestamp = Time.now() }]);
          #ok(if (isLike) "Liked" else "Disliked")
        }
      };
      case null {
        gameVoteEntries := Array.append<GameVote>(withoutMine, [{ gameId; voter = caller; isLike; timestamp = Time.now() }]);
        #ok(if (isLike) "Liked" else "Disliked")
      };
    }
  };

  // Batched read: for each game id, returns (likes, dislikes, myVote) in one call — same shape as
  // getHoleVoteSummary, so a list of game cards can render vote state without a round-trip per card.
  public query func getGameVoteSummary(ids : [Text], who : Principal) : async [(Text, Nat, Nat, ?Bool)] {
    Array.map<Text, (Text, Nat, Nat, ?Bool)>(ids, func(id) {
      let (likes, dislikes) = gameVoteCounts(id);
      let mine = switch (findGameVote(id, who)) { case (?v) { ?v.isLike }; case null { null } };
      (id, likes, dislikes, mine)
    })
  };

  public shared(msg) func submitHoleLink(title : Text, description : Text, url : Text) : async Result.Result<Text, Text> {
    assert (not isBannedNow(msg.caller)); // banned: only withdrawals, claims and listing allowed
    let caller = msg.caller;
    if (Principal.isAnonymous(caller)) return #err("Connect wallet to submit to Blackhole");
    switch (muteBlockMessage(msg.caller)) { case (?m) { return #err(m) }; case null {} };
    switch (holePunishmentReason(caller)) {
      case (?reason) { return #err("You are restricted from submitting to Blackhole: " # reason) };
      case null {};
    };
    if (Text.size(title) == 0 or Text.size(description) == 0 or Text.size(url) == 0) {
      return #err("Fill out all three fields");
    };
    hydrateRuntimeStateIfNeeded();
    if (activeHoleSubmissionCount(caller) >= 3) {
      return #err("Max 3 active Hole submissions. Delete one before adding another.");
    };

    let ledgerFeeE8s = 10_000;
    let fromSub = principalToSubaccount(caller);
    let selfPrincipal = Principal.fromActor(ArcadeBackend);
    let bal = await ICP_LEDGER_ICRC1.icrc1_balance_of({ owner = selfPrincipal; subaccount = ?fromSub });
    if (bal < HOLE_SUBMISSION_FEE_E8S + ledgerFeeE8s) {
      return #err(
        "Not enough ICP in your arcade deposit. Blackhole submission costs 1 ICP. Available " #
        Nat.toText(bal) # " e8s; need " # Nat.toText(HOLE_SUBMISSION_FEE_E8S + ledgerFeeE8s) # " e8s including ledger fee."
      );
    };

    try {
      // Fee routes straight into the Operating Treasury subaccount — never touches the main
      // account that backs Tokens/Tickets, matching admin's request that this go to a safely
      // withdrawable profit pool.
      let transferResult = await ICP_LEDGER.icrc1_transfer({
        to = { owner = selfPrincipal; subaccount = ?BLACKHOLE_TREASURY_SUBACCOUNT };
        fee = null;
        memo = null;
        from_subaccount = ?fromSub;
        created_at_time = ?ledgerNow();
        amount = HOLE_SUBMISSION_FEE_E8S;
      });
      switch (transferResult) {
        case (#Ok(blockIndex)) {
          if (Option.isSome(claimedSet.get(blockIndex))) {
            return #err("Duplicate ICP ledger transfer: block " # Nat.toText(blockIndex));
          };
          claimedSet.put(blockIndex, true);
          holeSubmissionCounter += 1;
          let id = "hole-" # Nat.toText(holeSubmissionCounter);
          let creatorName = switch (playerProfiles.get(caller)) {
            case (?p) { p.name };
            case null { Principal.toText(caller) };
          };
          let submission : HoleSubmission = {
            id;
            title;
            description;
            url;
            creator = caller;
            creatorNameSnapshot = creatorName;
            createdAt = Time.now();
            upvotes = 0;
            status = "active";
            isLegendary = false;
          };
          holeSubmissionEntries := Array.append<HoleSubmission>(holeSubmissionEntries, [submission]);
          logRevenue("blackhole-submit", HOLE_SUBMISSION_FEE_E8S, caller, 7);
          #ok(id)
        };
        case (#Err(e)) { #err(icpTransferErrorText("Blackhole submission fee", e)) };
      }
    } catch (e) {
      #err("Blackhole submission fee transfer error: " # Error.message(e))
    }
  };

  public query func getHoleSubmissions(sortBy : Text) : async [HoleSubmission] {
    let active = Array.filter<HoleSubmission>(holeSubmissionEntries, func(s) { s.status == "active" });
    if (sortBy == "top") {
      // Top Signal only shows submissions that have actually earned at least one like — a brand
      // new upload with zero engagement shouldn't appear here just because nothing else exists
      // yet; it belongs in Newest until the community actually likes it.
      let liked = Array.filter<HoleSubmission>(active, func(s) { let (likes, _) = holeVoteCounts(s.id); likes > 0 });
      let arr = Array.thaw<HoleSubmission>(liked);
      Array.sortInPlace<HoleSubmission>(arr, func(a, b) {
        let (aLikes, aDislikes) = holeVoteCounts(a.id);
        let (bLikes, bDislikes) = holeVoteCounts(b.id);
        let aScore : Int = aLikes - aDislikes;
        let bScore : Int = bLikes - bDislikes;
        Int.compare(bScore, aScore)
      });
      Array.freeze<HoleSubmission>(arr)
    } else {
      let arr = Array.thaw<HoleSubmission>(active);
      Array.sortInPlace<HoleSubmission>(arr, func(a, b) { Int.compare(b.createdAt, a.createdAt) });
      Array.freeze<HoleSubmission>(arr)
    }
  };

  public query func getHoleSubmission(id : Text) : async ?HoleSubmission {
    switch (findHoleSubmission(id)) {
      case (?s) { if (s.status == "active") { ?s } else { null } };
      case null { null };
    }
  };

  public query func getMyHoleSubmissions(who : Principal) : async [HoleSubmission] {
    Array.filter<HoleSubmission>(holeSubmissionEntries, func(s) {
      Principal.equal(s.creator, who) and s.status == "active"
    })
  };

  public shared(msg) func deleteHoleSubmission(id : Text) : async Result.Result<Text, Text> {
    assert (not isBannedNow(msg.caller)); // banned: only withdrawals, claims and listing allowed
    switch (findHoleSubmission(id)) {
      case null { #err("Submission not found") };
      case (?s) {
        if (not (Principal.equal(s.creator, msg.caller) or isAdmin(msg.caller) or isModerator(msg.caller))) {
          return #err("Not authorized to delete this submission");
        };
        holeSubmissionEntries := Array.map<HoleSubmission, HoleSubmission>(holeSubmissionEntries, func(item) {
          if (item.id == id) {
            {
              id = item.id; title = item.title; description = item.description; url = item.url;
              creator = item.creator; creatorNameSnapshot = item.creatorNameSnapshot; createdAt = item.createdAt;
              upvotes = item.upvotes; status = "deleted"; isLegendary = item.isLegendary;
            }
          } else { item }
        });
        #ok("Submission deleted")
      };
    }
  };

  // VP-gated like/dislike voting. One vote per principal per submission regardless of how much
  // voting power they hold (not weighted) — self-voting on your own submission is allowed, and
  // once cast a vote cannot be switched or removed, per Jay's spec.
  public shared(msg) func voteHoleSubmission(id : Text, isLike : Bool) : async Result.Result<Text, Text> {
    assert (not isBannedNow(msg.caller)); // banned: only withdrawals, claims and listing allowed
    let caller = msg.caller;
    if (Principal.isAnonymous(caller)) return #err("Connect wallet to vote");
    if (votingPowerOf(caller) == 0 and not isAdmin(caller)) return #err("Only Voting Power holders can vote on Blackhole submissions");
    switch (findHoleSubmission(id)) {
      case null { return #err("Submission not found") };
      case (?s) { if (s.status != "active") return #err("Submission not found") };
    };
    if (Option.isSome(findHoleVote(id, caller))) {
      return #err("You've already voted on this submission");
    };
    holeVoteEntries := Array.append<HoleVote>(holeVoteEntries, [{ submissionId = id; voter = caller; isLike; timestamp = Time.now() }]);
    #ok(if (isLike) "Liked" else "Disliked")
  };

  // Batched read: for each submission id, returns (likes, dislikes, myVote) in one call, so a
  // list of submissions can render vote counts and this viewer's own vote state without a
  // round-trip per card.
  public query func getHoleVoteSummary(ids : [Text], who : Principal) : async [(Text, Nat, Nat, ?Bool)] {
    Array.map<Text, (Text, Nat, Nat, ?Bool)>(ids, func(id) {
      let (likes, dislikes) = holeVoteCounts(id);
      let mine = switch (findHoleVote(id, who)) { case (?v) { ?v.isLike }; case null { null } };
      (id, likes, dislikes, mine)
    })
  };

  public shared(msg) func upvoteHoleSubmission(id : Text) : async Result.Result<Nat, Text> {
    assert (not isBannedNow(msg.caller)); // banned: only withdrawals, claims and listing allowed
    if (Principal.isAnonymous(msg.caller)) return #err("Connect wallet to signal approval");
    switch (findHoleSubmission(id)) {
      case null { #err("Submission not found") };
      case (?s) {
        if (s.status != "active") return #err("Submission not found");
        let newUpvotes = s.upvotes + 1;
        holeSubmissionEntries := Array.map<HoleSubmission, HoleSubmission>(holeSubmissionEntries, func(item) {
          if (item.id == id) {
            {
              id = item.id; title = item.title; description = item.description; url = item.url;
              creator = item.creator; creatorNameSnapshot = item.creatorNameSnapshot; createdAt = item.createdAt;
              upvotes = newUpvotes; status = item.status; isLegendary = item.isLegendary;
            }
          } else { item }
        });
        #ok(newUpvotes)
      };
    }
  };

  public shared(msg) func setHoleLegendary(id : Text, isLegendary : Bool) : async Result.Result<Text, Text> {
    assert (not isBannedNow(msg.caller)); // banned: only withdrawals, claims and listing allowed
    if (not isAdmin(msg.caller)) return #err("Admin only");
    switch (findHoleSubmission(id)) {
      case null { #err("Submission not found") };
      case (?s) {
        holeSubmissionEntries := Array.map<HoleSubmission, HoleSubmission>(holeSubmissionEntries, func(item) {
          if (item.id == id) {
            {
              id = item.id; title = item.title; description = item.description; url = item.url;
              creator = item.creator; creatorNameSnapshot = item.creatorNameSnapshot; createdAt = item.createdAt;
              upvotes = item.upvotes; status = item.status; isLegendary = isLegendary;
            }
          } else { item }
        });
        #ok(if (isLegendary) "Legendary granted" else "Legendary removed")
      };
    }
  };

  // Admin-only for now — Jay's to-do: extend this power to moderators once the moderator-powers
  // system is built out.
  public shared(msg) func adminSoftPunishBlackholeUploader(who : Principal, reason : Text) : async Result.Result<Text, Text> {
    assert (not isBannedNow(msg.caller)); // banned: only withdrawals, claims and listing allowed
    if (not isAdmin(msg.caller)) return #err("Admin only");
    let punishment : HolePunishment = { principal = who; until = Time.now() + HOLE_SOFT_PUNISH_NS; permanent = false; reason };
    holePunishmentEntries := Array.append<HolePunishment>(
      Array.filter<HolePunishment>(holePunishmentEntries, func(p) { not Principal.equal(p.principal, who) }),
      [punishment]
    );
    #ok("Uploader soft-punished for 7 days")
  };

  // Admin-only for now — same to-do as above. Hard ban also removes the uploader's existing
  // active submissions, since a permanent ban is reserved for real abuse (not just a cooldown).
  public shared(msg) func adminHardBanBlackholeUploader(who : Principal, reason : Text) : async Result.Result<Text, Text> {
    assert (not isBannedNow(msg.caller)); // banned: only withdrawals, claims and listing allowed
    if (not isAdmin(msg.caller)) return #err("Admin only");
    let punishment : HolePunishment = { principal = who; until = 0; permanent = true; reason };
    holePunishmentEntries := Array.append<HolePunishment>(
      Array.filter<HolePunishment>(holePunishmentEntries, func(p) { not Principal.equal(p.principal, who) }),
      [punishment]
    );
    holeSubmissionEntries := Array.map<HoleSubmission, HoleSubmission>(holeSubmissionEntries, func(item) {
      if (Principal.equal(item.creator, who) and item.status == "active") {
        {
          id = item.id; title = item.title; description = item.description; url = item.url;
          creator = item.creator; creatorNameSnapshot = item.creatorNameSnapshot; createdAt = item.createdAt;
          upvotes = item.upvotes; status = "deleted"; isLegendary = item.isLegendary;
        }
      } else { item }
    });
    #ok("Uploader permanently banned from Blackhole")
  };

  // Admin-only for now — same to-do as above.
  public shared(msg) func adminClearBlackholePunishment(who : Principal) : async Result.Result<Text, Text> {
    assert (not isBannedNow(msg.caller)); // banned: only withdrawals, claims and listing allowed
    if (not isAdmin(msg.caller)) return #err("Admin only");
    holePunishmentEntries := Array.filter<HolePunishment>(holePunishmentEntries, func(p) { not Principal.equal(p.principal, who) });
    #ok("Blackhole punishment cleared")
  };

  // Withdraw ICP from user's arcade deposit to a principal
  // subaccountHex: the 32-byte subaccount as 64-char hex (passed from frontend to avoid JS/Motoko encoding mismatch)
  public shared(msg) func withdrawDeposit(toPrincipal : Principal, amountE8s : Nat, subaccountHex : Text) : async Result.Result<Nat, Text> {
    let caller = msg.caller;
    if (Principal.isAnonymous(caller)) return #err("Must be authenticated");
    if (amountE8s < 20000) return #err("Minimum withdrawal: 0.0002 ICP");

    let fromSubOpt = hexToBlob(subaccountHex);
    let fromSub = switch(fromSubOpt) { case(?b) b; case(null) return #err("Invalid subaccount hex") };
    let expectedSub = principalToSubaccount(caller);
    if (not Text.equal(blobToHex(fromSub), blobToHex(expectedSub))) {
      return #err("Withdrawal subaccount does not belong to caller");
    };

    // Pre-check: verify we can see the balance
    let selfPrincipal = Principal.fromActor(ArcadeBackend);
    let bal = await ICP_LEDGER_ICRC1.icrc1_balance_of({ owner = selfPrincipal; subaccount = ?fromSub });
    if (bal == 0) return #err("Pre-check failed: backend sees 0 balance for sub=" # subaccountHex # " owner=" # Principal.toText(selfPrincipal));
    if (bal < amountE8s + 10000) return #err("Pre-check: only " # Nat.toText(bal) # " e8s available (need " # Nat.toText(amountE8s + 10000) # ")");

    try {
      let result = await ICP_LEDGER.icrc1_transfer({
        to = { owner = toPrincipal; subaccount = null };
        fee = null;
        memo = null;
        from_subaccount = ?fromSub;
        created_at_time = ?ledgerNow();
        amount = amountE8s;
      });
      switch (result) {
        case (#Ok(blockIndex)) { #ok(blockIndex) };
        case (#Err(e)) {
          switch (e) {
            case (#InsufficientFunds(f)) { #err("Insufficient funds: " # Nat.toText(f.balance) # " e8s available") };
            case (#BadFee(f)) { #err("Bad fee: expected " # Nat.toText(f.expected_fee)) };
            case (_) { #err("Transfer failed") };
          }
        };
      }
    } catch (e) {
      #err("Transfer error: " # Error.message(e))
    }
  };

  // Withdraw ICP to an account ID (hex) — for OISY/NNS style addresses
  public shared(msg) func withdrawDepositToAccount(toAccountHex : Text, amountE8s : Nat, subaccountHex : Text) : async Result.Result<Nat, Text> {
    let caller = msg.caller;
    if (Principal.isAnonymous(caller)) return #err("Must be authenticated");
    if (amountE8s < 20000) return #err("Minimum withdrawal: 0.0002 ICP");

    let fromSubOpt = hexToBlob(subaccountHex);
    let fromSub = switch(fromSubOpt) { case(?b) b; case(null) return #err("Invalid subaccount hex, len=" # Nat.toText(Text.size(subaccountHex))) };

    // Pre-check: compare frontend vs backend subaccount derivation
    let backendSub = principalToSubaccount(caller);
    let backendSubArr = Blob.toArray(backendSub);
    var backendSubHex = "";
    for (b in backendSubArr.vals()) {
      let hi = Nat8.toNat(b) / 16;
      let lo = Nat8.toNat(b) % 16;
      backendSubHex := backendSubHex # hexNibble(hi) # hexNibble(lo);
    };
    if (not Text.equal(blobToHex(fromSub), backendSubHex)) {
      return #err("Withdrawal subaccount does not belong to caller");
    };

    // Check balance with BOTH subaccounts
    let selfPrincipal = Principal.fromActor(ArcadeBackend);
    let balFrontend = await ICP_LEDGER_ICRC1.icrc1_balance_of({ owner = selfPrincipal; subaccount = ?fromSub });
    let balBackend = await ICP_LEDGER_ICRC1.icrc1_balance_of({ owner = selfPrincipal; subaccount = ?backendSub });

    if (balFrontend == 0 and balBackend == 0) return #err(
      "Both 0! frontSub=" # subaccountHex #
      " backSub=" # backendSubHex #
      " caller=" # Principal.toText(caller) #
      " match=" # (if (subaccountHex == backendSubHex) "YES" else "NO")
    );
    if (balFrontend == 0 and balBackend > 0) return #err(
      "Frontend sub=0, backend sub=" # Nat.toText(balBackend) # "e8s. Mismatch! Using backend sub instead. frontSub=" # subaccountHex # " backSub=" # backendSubHex
    );

    let toBytes = hexToBlob(toAccountHex);
    switch (toBytes) {
      case (null) { return #err("Invalid account ID format") };
      case (?_dest) {
        let oldLedger : actor { transfer : shared {
          to : Blob; fee : { e8s : Nat64 }; memo : Nat64;
          from_subaccount : ?Blob; created_at_time : ?{ timestamp_nanos : Nat64 };
          amount : { e8s : Nat64 }
        } -> async { #Ok : Nat64; #Err : {
          #BadFee : { expected_fee : { e8s : Nat64 } };
          #InsufficientFunds : { balance : { e8s : Nat64 } };
          #TxTooOld : { allowed_window_nanos : Nat64 };
          #TxCreatedInFuture; #TxDuplicate : { duplicate_of : Nat64 }
        }} } = actor("ryjl3-tyaaa-aaaaa-aaaba-cai");

        try {
          let result = await oldLedger.transfer({
            to = _dest;
            fee = { e8s = 10_000 : Nat64 };
            memo = 0 : Nat64;
            from_subaccount = ?fromSub;
            created_at_time = null;
            amount = { e8s = Nat64.fromNat(amountE8s) };
          });
          switch (result) {
            case (#Ok(blockIndex)) { #ok(Nat64.toNat(blockIndex)) };
            case (#Err(e)) {
              switch (e) {
                case (#InsufficientFunds(f)) { #err("Insufficient funds: " # Nat64.toText(f.balance.e8s) # " e8s available") };
                case (#BadFee(f)) { #err("Bad fee: expected " # Nat64.toText(f.expected_fee.e8s)) };
                case (_) { #err("Transfer failed") };
              }
            };
          }
        } catch (e) {
          #err("Transfer error: " # Error.message(e))
        }
      };
    }
  };

  // Helper: hex string to Blob (32 bytes)
  func hexToBlob(hex : Text) : ?Blob {
    let chars = Text.toArray(hex);
    if (chars.size() != 64) return null;
    for (c in chars.vals()) {
      if (not isHexChar(c)) return null;
    };
    let bytes = Array.tabulate<Nat8>(32, func(i : Nat) : Nat8 {
      let hi = hexCharToNat(chars[i * 2]);
      let lo = hexCharToNat(chars[i * 2 + 1]);
      Nat8.fromNat(hi * 16 + lo);
    });
    ?Blob.fromArray(bytes);
  };

  func isHexChar(c : Char) : Bool {
    let n = Nat32.toNat(Nat32.fromNat(Nat32.toNat(Char.toNat32(c))));
    (n >= 48 and n <= 57) or (n >= 97 and n <= 102) or (n >= 65 and n <= 70)
  };

  func hexCharToNat(c : Char) : Nat {
    let n = Nat32.toNat(Nat32.fromNat(Nat32.toNat(Char.toNat32(c))));
    if (n >= 48 and n <= 57) { n - 48 }        // 0-9
    else if (n >= 97 and n <= 102) { n - 87 }   // a-f
    else if (n >= 65 and n <= 70) { n - 55 }     // A-F
    else { 0 }
  };

  // ICP Ledger ICRC-1 balance query (uses principal + subaccount, not account ID)
  type Icrc1Account = { owner : Principal; subaccount : ?Blob };
  transient let ICP_LEDGER_ICRC1 : actor { icrc1_balance_of : shared query Icrc1Account -> async Nat } = actor("ryjl3-tyaaa-aaaaa-aaaba-cai");

  public shared(msg) func debugSubaccount() : async { subHex : Text; callerText : Text; selfText : Text; balanceE8s : Nat } {
    let caller = msg.caller;
    let sub = principalToSubaccount(caller);
    let subArr = Blob.toArray(sub);
    var hex = "";
    for (b in subArr.vals()) {
      let hi = Nat8.toNat(b) / 16;
      let lo = Nat8.toNat(b) % 16;
      hex := hex # hexNibble(hi) # hexNibble(lo);
    };
    let selfPrincipal = Principal.fromActor(ArcadeBackend);
    let bal = await ICP_LEDGER_ICRC1.icrc1_balance_of({ owner = selfPrincipal; subaccount = ?sub });
    { subHex = hex; callerText = Principal.toText(caller); selfText = Principal.toText(selfPrincipal); balanceE8s = bal }
  };

  func hexNibble(n : Nat) : Text {
    let chars = ["0","1","2","3","4","5","6","7","8","9","a","b","c","d","e","f"];
    chars[n % 16]
  };


  // === SHARED FORUMS / DAO PROPOSALS (PHASE 2) ===
  func isAnonymousPrincipal(p : Principal) : Bool { Principal.toText(p) == "2vxsx-fae" };

  let FORUM_SECTION_MAX_CHARS : Nat = 64;
  let FORUM_TITLE_MAX_CHARS : Nat = 120;
  let FORUM_BODY_MAX_CHARS : Nat = 4_000;
  let FORUM_REPLY_BODY_MAX_CHARS : Nat = 2_000;
  let FORUM_AUTHOR_MAX_CHARS : Nat = 80;
  let FORUM_IMAGE_REF_MAX_CHARS : Nat = 512;

  func isDaoSection(section : Text) : Bool {
    section == "dao" or Text.startsWith(section, #text("dao-"));
  };

  func votingPowerOf(owner : Principal) : Nat {
    // Session #3 rules: admin holds no VP; 1 VP per VP Badge; Dev and Artist contributor badges add 1 each
    // (each type counted once, ignoring the old stored weight of 5 and any duplicates).
    if (isAdmin(owner)) return 0;
    var vp : Nat = 0;
    var dev = false;
    var artist = false;
    for (badge in getBadgesForOwner(owner).vals()) {
      if (Text.startsWith(badge.badgeType, #text "vp-badge-")) { vp += 1 }
      else if (badge.badgeType == "dev-contributor") { dev := true }
      else if (badge.badgeType == "artist-contributor") { artist := true };
    };
    vp + (if (dev) 1 else 0) + (if (artist) 1 else 0) + abilityCountOf(owner, "vp-plus");
  };

  // DAO forum access by section. Base DAO sections need any VP; tiers count VP Badges only (5 / 7 / 10);
  // contributor sections need that contributor badge. Admin can access every section.
  func daoSectionAllowed(p : Principal, section : Text) : Bool {
    if (not isDaoSection(section)) return true;
    if (isAdmin(p)) return true;
    let perks = abilityInstancesOf(p);
    func perkHas(id : Text) : Bool { for ((a, _) in perks.vals()) { if (a == id) return true }; false };
    if (perkHas("access-all")) return true;
    if (section == "dao-game-developers" and perkHas("access-dev")) return true;
    if (section == "dao-artists" and perkHas("access-art")) return true;
    if (section == "dao-voting" and perkHas("access-veteran")) return true;
    if (section == "dao-player-portal" and perkHas("access-elite")) return true;
    if (section == "dao-core" and perkHas("access-diplomat")) return true;
    if (votingPowerOf(p) == 0) return false;
    let n = vpBadgeCountOf(p);
    if (section == "dao-voting" or section == "dao-treasury") return n >= 5;
    if (section == "dao-player-portal") return n >= 7;
    if (section == "dao-core") return n >= 10;
    if (section == "dao-game-developers") {
      for (b in getBadgesForOwner(p).vals()) { if (b.badgeType == "dev-contributor") return true };
      return false;
    };
    if (section == "dao-artists") {
      for (b in getBadgesForOwner(p).vals()) { if (b.badgeType == "artist-contributor") return true };
      return false;
    };
    true
  };

  // Raw count of VP Badges held, distinct from votingPowerOf's weighted total (currently 5 per
  // badge) — used for DXP, where each badge held contributes exactly 1 vote per proposal.
  func badgeCountOf(owner : Principal) : Nat {
    getBadgesForOwner(owner).size();
  };

  func hasContributorBadge(owner : Principal) : Bool {
    for (badge in getBadgesForOwner(owner).vals()) {
      if (
        badge.badgeType == "dev-contributor" or
        badge.badgeType == "artist-contributor" or
        badge.badgeType == "gashapon-contributor"
      ) return true;
    };
    false;
  };

  func hasDaoAccess(owner : Principal) : Bool {
    isAdmin(owner) or votingPowerOf(owner) > 0;
  };

  func hasForumMediaAccess(owner : Principal) : Bool {
    isAdmin(owner) or votingPowerOf(owner) > 0 or hasContributorBadge(owner);
  };

  func validateForumText(value : Text, field : Text, maxChars : Nat, required : Bool) : Result.Result<(), Text> {
    let trimmed = Text.trim(value, #char ' ');
    if (required and Text.size(trimmed) == 0) return #err(field # " required");
    if (Text.size(value) > maxChars) return #err(field # " too long");
    #ok(())
  };

  func isAllowedForumImageRef(value : Text) : Bool {
    Text.startsWith(value, #text("https://")) or
    Text.startsWith(value, #text("http://")) or
    Text.startsWith(value, #text("ipfs://")) or
    Text.startsWith(value, #text("ar://")) or
    Text.startsWith(value, #text("asset:")) or
    Text.startsWith(value, #text("/uploads/")) or
    Text.startsWith(value, #text("/assets/"))
  };

  func validateForumImage(caller : Principal, image : ?Text) : Result.Result<?Text, Text> {
    switch (image) {
      case null { #ok(null) };
      case (?raw) {
        let value = Text.trim(raw, #char ' ');
        if (Text.size(value) == 0) return #ok(null);
        if (not hasForumMediaAccess(caller)) return #err("Forum image posting requires Voting Power, contributor badge, or admin access");
        if (Text.size(value) > FORUM_IMAGE_REF_MAX_CHARS) return #err("Forum image reference too long");
        if (
          Text.startsWith(value, #text("data:")) or
          Text.contains(value, #text(";base64,")) or
          Text.contains(value, #text("base64,"))
        ) return #err("Inline/base64 forum images are not allowed; use a compact URL or asset reference");
        if (not isAllowedForumImageRef(value)) return #err("Forum image must be an http(s), ipfs, arweave, or asset reference");
        #ok(?value)
      };
    }
  };

  func publicForumThread(thread : ForumThread) : Bool { not thread.deleted };

  func proposalIsActive(proposal : Proposal, now : Int) : Bool {
    (not proposal.closed) and now < proposal.endsAt;
  };

  func durationToNs(duration : Text) : Int {
    if (duration == "1d") return 86_400_000_000_000;
    if (duration == "7d") return 604_800_000_000_000;
    259_200_000_000_000;
  };

  public shared query (msg) func getForumThreads(section : Text) : async [ForumThread] {
    if (not daoSectionAllowed(msg.caller, section)) return [];
    ensureForumIndexBuilt();
    switch (threadIdsBySection.get(section)) {
      case null { [] };
      case (?bucket) {
        let result = Buffer.Buffer<ForumThread>(bucket.size());
        for (id in bucket.vals()) {
          switch (threadsById.get(id)) {
            case (?thread) { if (publicForumThread(thread)) { result.add(thread) } };
            case null {};
          };
        };
        Buffer.toArray(result);
      };
    };
  };

  public shared(msg) func createForumThread(section : Text, title : Text, body : Text, image : ?Text, authorName : Text) : async Result.Result<Text, Text> {
    assert (not isBannedNow(msg.caller)); // banned: only withdrawals, claims and listing allowed
    if (isAnonymousPrincipal(msg.caller)) return #err("Connect wallet to post");
    switch (muteBlockMessage(msg.caller)) { case (?m) { return #err(m) }; case null {} };
    switch (validateForumText(section, "Section", FORUM_SECTION_MAX_CHARS, true)) { case (#err(e)) return #err(e); case (#ok(())) {} };
    switch (validateForumText(title, "Title", FORUM_TITLE_MAX_CHARS, true)) { case (#err(e)) return #err(e); case (#ok(())) {} };
    switch (validateForumText(body, "Body", FORUM_BODY_MAX_CHARS, false)) { case (#err(e)) return #err(e); case (#ok(())) {} };
    switch (validateForumText(authorName, "Author", FORUM_AUTHOR_MAX_CHARS, false)) { case (#err(e)) return #err(e); case (#ok(())) {} };
    let normalizedImage = switch (validateForumImage(msg.caller, image)) { case (#ok(v)) v; case (#err(e)) return #err(e) };
    if (Text.size(Text.trim(body, #char ' ')) == 0 and Option.isNull(normalizedImage)) return #err("Body required for text-first forum posting");
    if (not daoSectionAllowed(msg.caller, section)) return #err("You don't have access to post in this DAO section");
    // One new thread per rolling 24h per player, counted separately for the forums and the DAO (admins exempt).
    // Deleted threads still count, so delete-and-repost can't bypass it. No new storage: scans existing threads.
    if (not isAdmin(msg.caller)) {
      let now = Time.now();
      let dayNs : Int = 86_400_000_000_000;
      let wantDao = isDaoSection(section);
      var inWindow : Nat = 0;
      var oldestInWindow : Int = now;
      for (t in forumThreadEntries.vals()) {
        if (Principal.equal(t.author, msg.caller) and isDaoSection(t.section) == wantDao and now - t.createdAt < dayNs) {
          inWindow += 1;
          if (t.createdAt < oldestInWindow) { oldestInWindow := t.createdAt };
        };
      };
      let allowedThreads : Nat = 1 + abilityCountOf(msg.caller, "forum-thread-plus");
      if (inWindow >= allowedThreads) {
        let remainMin : Nat = Nat64.toNat(Nat64.fromIntWrap((dayNs - (now - oldestInWindow)) / 60_000_000_000)) + 1;
        return #err("You can start " # Nat.toText(allowedThreads) # " new " # (if (wantDao) "DAO thread" else "forum thread") # (if (allowedThreads == 1) "" else "s") # " per day. Next one opens in " # Nat.toText(remainMin / 60) # "h " # Nat.toText(remainMin % 60) # "m.");
      };
    };
    forumThreadCounter += 1;
    let id = "forum-" # Nat.toText(forumThreadCounter);
    let thread : ForumThread = {
      id = id;
      section = section;
      title = title;
      body = body;
      image = normalizedImage;
      author = msg.caller;
      authorName = authorName;
      createdAt = Time.now();
      replies = [];
      deleted = false;
    };
    ensureForumIndexBuilt(); // build the index BEFORE adding the new thread; otherwise the first post after an upgrade is indexed twice
    forumThreadEntries := Array.append<ForumThread>([thread], forumThreadEntries);
    addThreadToIndex(thread);
    #ok(id)
  };

  public shared(msg) func addForumReply(threadId : Text, body : Text, image : ?Text, authorName : Text, parentReplyId : ?Text) : async Result.Result<Text, Text> {
    assert (not isBannedNow(msg.caller)); // banned: only withdrawals, claims and listing allowed
    if (isAnonymousPrincipal(msg.caller)) return #err("Connect wallet to reply");
    switch (muteBlockMessage(msg.caller)) { case (?m) { return #err(m) }; case null {} };
    switch (validateForumText(threadId, "Thread", FORUM_SECTION_MAX_CHARS, true)) { case (#err(e)) return #err(e); case (#ok(())) {} };
    switch (validateForumText(body, "Reply body", FORUM_REPLY_BODY_MAX_CHARS, false)) { case (#err(e)) return #err(e); case (#ok(())) {} };
    switch (validateForumText(authorName, "Author", FORUM_AUTHOR_MAX_CHARS, false)) { case (#err(e)) return #err(e); case (#ok(())) {} };
    let normalizedImage = switch (validateForumImage(msg.caller, image)) { case (#ok(v)) v; case (#err(e)) return #err(e) };
    if (Text.size(Text.trim(body, #char ' ')) == 0 and Option.isNull(normalizedImage)) return #err("Reply body required for text-first forum posting");
    ensureForumIndexBuilt();
    var found = false;
    var rejected : ?Text = null;
    var updatedThread : ?ForumThread = null;
    forumThreadCounter += 1;
    let replyId = "reply-" # Nat.toText(forumThreadCounter);
    forumThreadEntries := Array.map<ForumThread, ForumThread>(forumThreadEntries, func(thread) {
      if (thread.id != threadId or thread.deleted) return thread;
      found := true;
      if (not daoSectionAllowed(msg.caller, thread.section)) {
        rejected := ?"Voting Power Badge required for DAO replies";
        return thread;
      };
      switch (parentReplyId) {
        case null {};
        case (?pid) {
          var parentOk = false;
          for (existing in thread.replies.vals()) {
            if (existing.id == pid and Option.isNull(existing.parentReplyId)) parentOk := true;
          };
          if (not parentOk) {
            rejected := ?"Parent reply not found or nesting too deep";
            return thread;
          };
        };
      };
      let reply : ForumReply = {
        id = replyId;
        threadId = threadId;
        body = body;
        image = normalizedImage;
        author = msg.caller;
        authorName = authorName;
        createdAt = Time.now();
        parentReplyId = parentReplyId;
      };
      let updated : ForumThread = {
        id = thread.id;
        section = thread.section;
        title = thread.title;
        body = thread.body;
        image = thread.image;
        author = thread.author;
        authorName = thread.authorName;
        createdAt = thread.createdAt;
        replies = Array.append<ForumReply>(thread.replies, [reply]);
        deleted = thread.deleted;
      };
      updatedThread := ?updated;
      updated
    });
    switch (rejected) { case (?reason) { return #err(reason) }; case null {} };
    if (not found) return #err("Thread not found");
    switch (updatedThread) { case (?t) { threadsById.put(t.id, t) }; case null {} };
    #ok(replyId)
  };

  /// Real thread deletion — was previously entirely fake on the frontend (local cache/localStorage
  /// only, never touched the backend, so "deleted" threads reappeared for anyone else and on
  /// refresh). Soft-deletes via the existing `deleted` flag (already read by publicForumThread,
  /// but never set anywhere until now) rather than removing the record outright.
  public shared(msg) func adminDeleteForumThread(threadId : Text) : async Result.Result<Text, Text> {
    assert (not isBannedNow(msg.caller)); // banned: only withdrawals, claims and listing allowed
    ensureForumIndexBuilt();
    var found = false;
    var authorized = false;
    var updatedThread : ?ForumThread = null;
    forumThreadEntries := Array.map<ForumThread, ForumThread>(forumThreadEntries, func(thread) {
      if (thread.id != threadId) return thread;
      found := true;
      if (not (Principal.equal(thread.author, msg.caller) or isAdmin(msg.caller) or isModerator(msg.caller))) {
        return thread;
      };
      authorized := true;
      let updated : ForumThread = {
        id = thread.id;
        section = thread.section;
        title = thread.title;
        body = thread.body;
        image = thread.image;
        author = thread.author;
        authorName = thread.authorName;
        createdAt = thread.createdAt;
        replies = thread.replies;
        deleted = true;
      };
      updatedThread := ?updated;
      updated
    });
    if (not found) return #err("Thread not found");
    if (not authorized) return #err("Not authorized to delete this thread");
    switch (updatedThread) { case (?t) { threadsById.put(t.id, t) }; case null {} };
    #ok("Thread deleted")
  };

  /// Real reply deletion — same previously-fake local-only bug as thread deletion above. Replies
  /// have no `deleted` flag of their own (adding one would require a stable-type shape change,
  /// risking a memory-incompatible upgrade), so this hard-removes the reply and any of its own
  /// nested child replies from the thread's replies array instead.
  public shared(msg) func adminDeleteForumReply(threadId : Text, replyId : Text) : async Result.Result<Text, Text> {
    assert (not isBannedNow(msg.caller)); // banned: only withdrawals, claims and listing allowed
    ensureForumIndexBuilt();
    var found = false;
    var authorized = false;
    var replyFound = false;
    var updatedThread : ?ForumThread = null;
    forumThreadEntries := Array.map<ForumThread, ForumThread>(forumThreadEntries, func(thread) {
      if (thread.id != threadId) return thread;
      found := true;
      var targetAuthor : ?Principal = null;
      for (r in thread.replies.vals()) {
        if (r.id == replyId) { targetAuthor := ?r.author; replyFound := true };
      };
      switch (targetAuthor) {
        case null { return thread };
        case (?author) {
          if (not (Principal.equal(author, msg.caller) or isAdmin(msg.caller) or isModerator(msg.caller))) {
            return thread;
          };
        };
      };
      authorized := true;
      let remainingReplies = Array.filter<ForumReply>(thread.replies, func(r) {
        r.id != replyId and r.parentReplyId != ?replyId
      });
      let updated : ForumThread = {
        id = thread.id;
        section = thread.section;
        title = thread.title;
        body = thread.body;
        image = thread.image;
        author = thread.author;
        authorName = thread.authorName;
        createdAt = thread.createdAt;
        replies = remainingReplies;
        deleted = thread.deleted;
      };
      updatedThread := ?updated;
      updated
    });
    if (not found) return #err("Thread not found");
    if (not replyFound) return #err("Reply not found");
    if (not authorized) return #err("Not authorized to delete this reply");
    switch (updatedThread) { case (?t) { threadsById.put(t.id, t) }; case null {} };
    #ok("Reply deleted")
  };

  public query func getGamerBadges(owner : Principal) : async [GamerBadge] {
    getBadgesForOwner(owner);
  };

  public query func getVotingPower(owner : Principal) : async Nat { votingPowerOf(owner) };

  public shared(msg) func awardDevContributorBadge(owner : Principal, gameId : Text) : async Result.Result<Text, Text> {
    assert (not isBannedNow(msg.caller)); // banned: only withdrawals, claims and listing allowed
    if (not isAdmin(msg.caller)) return #err("Admin only");
    if (isAdmin(owner)) return #err("Admin accounts don't hold badges");
    for (b in getBadgesForOwner(owner).vals()) { if (b.badgeType == "dev-contributor") return #err("This account already has a Dev Contributor badge") };
    gamerBadgeCounter += 1;
    let badge : GamerBadge = { id = "badge-" # Nat.toText(gamerBadgeCounter); badgeType = "dev-contributor"; owner = owner; gameId = ?gameId; votingPower = 1; soulbound = true; createdAt = Time.now() };
    gamerBadgeEntries := Array.append<GamerBadge>(gamerBadgeEntries, [badge]);
    ensureBadgeIndexBuilt();
    addBadgeToIndex(badge);
    #ok(badge.id)
  };

  public shared(msg) func awardArtistContributorBadge(owner : Principal) : async Result.Result<Text, Text> {
    assert (not isBannedNow(msg.caller)); // banned: only withdrawals, claims and listing allowed
    if (not isAdmin(msg.caller)) return #err("Admin only");
    if (isAdmin(owner)) return #err("Admin accounts don't hold badges");
    for (b in getBadgesForOwner(owner).vals()) { if (b.badgeType == "artist-contributor") return #err("This account already has an Artist Contributor badge") };
    gamerBadgeCounter += 1;
    let badge : GamerBadge = { id = "badge-" # Nat.toText(gamerBadgeCounter); badgeType = "artist-contributor"; owner = owner; gameId = null; votingPower = 1; soulbound = true; createdAt = Time.now() };
    gamerBadgeEntries := Array.append<GamerBadge>(gamerBadgeEntries, [badge]);
    ensureBadgeIndexBuilt();
    addBadgeToIndex(badge);
    #ok(badge.id)
  };

  let VP_BADGE_COSTS : [Nat] = [1000, 2000, 3000, 5000, 7500, 10000, 15000, 20000, 25000, 50000];

  func vpBadgeCountOf(owner : Principal) : Nat {
    var count = 0;
    for (badge in getBadgesForOwner(owner).vals()) {
      if (Text.startsWith(badge.badgeType, #text "vp-badge-")) { count += 1 };
    };
    count
  };

  public shared(msg) func buyStandardBadge() : async Result.Result<Text, Text> {
    assert (not isBannedNow(msg.caller)); // banned: only withdrawals, claims and listing allowed
    if (isAnonymousPrincipal(msg.caller)) return #err("Connect wallet to buy a badge");
    if (isAdmin(msg.caller)) return #err("Admin accounts don't hold Voting Power Badges");
    let owned = vpBadgeCountOf(msg.caller);
    if (owned >= 10) return #err("All 10 Voting Power Badges already owned");
    let cost = VP_BADGE_COSTS[owned];
    let balance = getTicketBalance(msg.caller);
    if (balance < cost) return #err("Not enough tickets. This badge costs " # Nat.toText(cost) # " Tickets. Have " # Nat.toText(balance));
    tickets.put(msg.caller, balance - cost);
    // Prize Booth split for VP badges: arcade 80%, DAO 20% (of the spent tickets' ICP backing)
    let vpE8s = cost * TICKET_LIABILITY_E8S;
    let vpDaoE8s = vpE8s * 20 / 100;
    daoTreasuryE8s += vpDaoE8s;
    daoInVpBadgeE8s += vpDaoE8s;
    prizeBoothArcadeShareE8s += vpE8s - vpDaoE8s;
    gamerBadgeCounter += 1;
    let badge : GamerBadge = { id = "badge-" # Nat.toText(gamerBadgeCounter); badgeType = "vp-badge-" # Nat.toText(owned + 1); owner = msg.caller; gameId = null; votingPower = 1; soulbound = true; createdAt = Time.now() };
    gamerBadgeEntries := Array.append<GamerBadge>(gamerBadgeEntries, [badge]);
    ensureBadgeIndexBuilt();
    addBadgeToIndex(badge);
    #ok(badge.id)
  };

  public shared(msg) func adminResetVpBadges() : async Result.Result<Text, Text> {
    assert (not isBannedNow(msg.caller)); // banned: only withdrawals, claims and listing allowed
    if (not isAdmin(msg.caller)) return #err("Not authorized");
    gamerBadgeEntries := Array.filter<GamerBadge>(gamerBadgeEntries, func(badge) {
      not (Principal.equal(badge.owner, msg.caller) and Text.startsWith(badge.badgeType, #text "vp-badge-"))
    });
    ensureBadgeIndexBuilt();
    let remaining = Buffer.Buffer<GamerBadge>(4);
    for (badge in gamerBadgeEntries.vals()) {
      if (Principal.equal(badge.owner, msg.caller)) { remaining.add(badge) };
    };
    badgesByOwner.put(msg.caller, remaining);
    #ok("Voting Power Badges reset to 0")
  };

  public shared(msg) func adminAddExternalCollection(canisterId : Text, name : Text) : async Result.Result<Text, Text> {
    assert (not isBannedNow(msg.caller)); // banned: only withdrawals, claims and listing allowed
    if (not isAdmin(msg.caller)) return #err("Not authorized");
    hydrateRuntimeStateIfNeeded();
    if (Text.size(Text.trim(canisterId, #char ' ')) == 0) return #err("Canister ID required");
    if (Text.size(Text.trim(name, #char ' ')) == 0) return #err("Collection name required");
    externalCollections.put(canisterId, name);
    #ok("External collection registered")
  };

  public shared(msg) func adminRemoveExternalCollection(canisterId : Text) : async Result.Result<Text, Text> {
    assert (not isBannedNow(msg.caller)); // banned: only withdrawals, claims and listing allowed
    if (not isAdmin(msg.caller)) return #err("Not authorized");
    hydrateRuntimeStateIfNeeded();
    externalCollections.delete(canisterId);
    #ok("External collection removed")
  };

  public query func getExternalCollections() : async [(Text, Text)] {
    Iter.toArray(externalCollections.entries())
  };

  public shared(msg) func adminAddModerator(principal : Principal) : async Result.Result<Text, Text> {
    assert (not isBannedNow(msg.caller)); // banned: only withdrawals, claims and listing allowed
    if (not isAdmin(msg.caller)) return #err("Not authorized");
    hydrateRuntimeStateIfNeeded();
    switch (moderators.get(principal)) {
      case (?_) { #err("Already a moderator") };
      case null { moderators.put(principal, []); #ok("Moderator added") };
    }
  };

  public shared(msg) func adminRemoveModerator(principal : Principal) : async Result.Result<Text, Text> {
    assert (not isBannedNow(msg.caller)); // banned: only withdrawals, claims and listing allowed
    if (not isAdmin(msg.caller)) return #err("Not authorized");
    hydrateRuntimeStateIfNeeded();
    moderators.delete(principal);
    #ok("Moderator removed")
  };

  public query func getModerators() : async [Principal] {
    Iter.toArray(moderators.keys())
  };

  public shared(msg) func createProposal(title : Text, body : Text, category : Text, duration : Text, images : [Text], paymentLane : Text) : async Result.Result<Text, Text> {
    assert (not isBannedNow(msg.caller)); // banned: only withdrawals, claims and listing allowed
    if (isAnonymousPrincipal(msg.caller)) return #err("Connect wallet to create a proposal");
    switch (muteBlockMessage(msg.caller)) { case (?m) { return #err(m) }; case null {} };
    if (vpBadgeCountOf(msg.caller) < 2 and not isAdmin(msg.caller)) return #err("2 Voting Power Badges required to create proposals");
    if (Text.size(Text.trim(title, #char ' ')) == 0) return #err("Title required");
    if (Text.size(Text.trim(body, #char ' ')) == 0) return #err("Description required");
    if (not isAdmin(msg.caller) and recentProposalBy(msg.caller, Time.now())) return #err("You've reached your proposal limit for the last 24 hours");
    // Proposals cost 5 Tokens only (the paymentLane argument is kept for interface compatibility but ignored).
    if (not isAdmin(msg.caller)) {
      let tokenBal = getTokenBalance(msg.caller);
      if (tokenBal < 5) return #err("Not enough tokens. Creating a proposal costs 5 Tokens. Have " # Nat.toText(tokenBal));
      tokens.put(msg.caller, tokenBal - 5);
      // proposal fee -> DAO treasury: the 5 Tokens' ICP backing (1 Token = 0.01 ICP) moves to the DAO's ICP treasury
      daoTreasuryE8s += 5 * TOKEN_TIP_E8S_PER_TOKEN;
      daoInProposalsE8s += 5 * TOKEN_TIP_E8S_PER_TOKEN;
    };
    proposalCounter += 1;
    let now = Time.now();
    let proposal : Proposal = {
      id = "proposal-" # Nat.toText(proposalCounter);
      title = title;
      body = body;
      category = if (Text.size(category) == 0) "general" else category;
      official = isAdmin(msg.caller);
      images = images;
      author = msg.caller;
      authorName = Principal.toText(msg.caller);
      createdAt = now;
      endsAt = now + durationToNs(duration);
      duration = duration;
      votesFor = 0;
      votesAgainst = 0;
      votes = [];
      discussion = [];
      closed = false;
    };
    proposalEntries := Array.append<Proposal>([proposal], proposalEntries);
    addDxp(msg.caller, 10);
    #ok(proposal.id)
  };

  // === PROPOSAL TYPES (stage 1) ===
  // Side table keyed by proposal id, so the stored Proposal record never changes shape.
  // category holds the proposal type; multi-choice votes are stored as "c0".."c3" in ProposalVote.vote.
  type ProposalMeta = {
    kind : Text;
    choices : [Text];
    choiceTotals : [Nat];
    target : Text;          // "game:<id>" | "hole:<id>" | principal text | ""
    voterCount : Nat;       // weighted (non-admin) voters, for quorum
    execStatus : Text;      // "none" now; stage 2: "pending" | "executed" | "vetoed" | "failed"
    executeAfter : Int;     // stage 2 timelock
  };
  stable var proposalMetaEntries : [(Text, ProposalMeta)] = [];

  func findProposalMeta(id : Text) : ?ProposalMeta {
    for ((k, m) in proposalMetaEntries.vals()) { if (k == id) return ?m };
    null
  };
  func putProposalMeta(id : Text, m : ProposalMeta) {
    proposalMetaEntries := Array.append<(Text, ProposalMeta)>(Array.filter<(Text, ProposalMeta)>(proposalMetaEntries, func(e) { e.0 != id }), [(id, m)]);
  };
  func parseChoiceVote(v : Text, n : Nat) : ?Nat {
    var i : Nat = 0;
    while (i < n and i < 4) { if (v == "c" # Nat.toText(i)) return ?i; i += 1 };
    null
  };
  // True when the player has used up their proposals for the rolling 24h (1 + proposal-plus abilities).
  func recentProposalBy(who : Principal, now : Int) : Bool {
    var n : Nat = 0;
    for (p in proposalEntries.vals()) { if (Principal.equal(p.author, who) and now - p.createdAt < 86_400_000_000_000) { n += 1 } };
    n >= 1 + abilityCountOf(who, "proposal-plus")
  };

  public shared(msg) func createProposalV2(kind : Text, title : Text, body : Text, duration : Text, images : [Text], choices : [Text], target : Text) : async Result.Result<Text, Text> {
    assert (not isBannedNow(msg.caller)); // banned: only withdrawals, claims and listing allowed
    let caller = msg.caller;
    if (isAnonymousPrincipal(caller)) return #err("Connect wallet to create a proposal");
    switch (muteBlockMessage(msg.caller)) { case (?m) { return #err(m) }; case null {} };
    hydrateRuntimeStateIfNeeded();
    let admin = isAdmin(caller);
    let advisory : [Text] = ["recommend-game", "recommendation", "game-design-request", "general", "ban-user", "bug-report"];
    let devOnly : [Text] = ["contest", "community-choice", "artist-commission"];
    let controlling : [Text] = ["dao-favourite", "dao-favourite-remove", "mute-user", "content-removal"];
    let lockedKinds : [Text] = [];
    func inList(l : [Text]) : Bool { for (x in l.vals()) { if (x == kind) return true }; false };
    if (inList(lockedKinds)) return #err("This proposal type is coming soon");
    if (not inList(advisory) and not inList(devOnly) and not inList(controlling)) return #err("Unknown proposal type");
    if (inList(devOnly) and not admin) return #err("Only the Dev Team can create this proposal type");
    if (kind == "bug-report") {
      if (votingPowerOf(caller) == 0 and not admin) return #err("DAO membership (1 Voting Power) required to file a bug report");
    } else if (not admin and vpBadgeCountOf(caller) < 2) {
      return #err("2 Voting Power Badges required to create proposals");
    };
    if (Text.size(Text.trim(title, #char ' ')) == 0) return #err("Title required");
    if (Text.size(Text.trim(body, #char ' ')) == 0) return #err("Description required");
    let now = Time.now();
    if (not admin and recentProposalBy(caller, now)) return #err("You've reached your proposal limit for the last 24 hours");
    let cleaned = Buffer.Buffer<Text>(4);
    for (c in choices.vals()) { let t = Text.trim(c, #char ' '); if (Text.size(t) > 0) { cleaned.add(t) } };
    let multiRequired = inList(devOnly);
    if (multiRequired and (cleaned.size() < 2 or cleaned.size() > 4)) return #err("This proposal type needs 2 to 4 choices");
    if (kind == "general" and cleaned.size() != 0 and (cleaned.size() < 2 or cleaned.size() > 4)) return #err("General proposals need either no choices (For/Against) or 2 to 4 choices");
    if (not multiRequired and kind != "general" and cleaned.size() > 0) return #err("This proposal type is For/Against only");
    for (t in cleaned.vals()) { if (Text.size(t) > 80) return #err("Each choice must be 80 characters or fewer") };
    var tgt : Text = "";
    if (kind == "recommend-game") {
      switch (Text.stripStart(target, #text "game:")) {
        case (?gid) {
          switch (gameSubmissions.get(gid)) { case null { return #err("Game not found") }; case (?_) {} };
          tgt := target;
        };
        case null {
          switch (Text.stripStart(target, #text "hole:")) {
            case (?hid) {
              switch (findHoleSubmission(hid)) {
                case null { return #err("Blackhole entry not found") };
                case (?h) { if (h.status != "active") return #err("That Blackhole entry is no longer active") };
              };
              tgt := target;
            };
            case null { return #err("Pick a game from The Back or a Blackhole entry to recommend") };
          };
        };
      };
    };
    if (kind == "ban-user") {
      let who = Principal.fromText(target); // malformed text traps and nothing is saved; the UI validates first
      if (isAdmin(who)) return #err("The Dev Team can't be targeted");
      if (Principal.equal(who, caller)) return #err("You can't target yourself");
      tgt := Principal.toText(who);
    };
    if (kind == "dao-favourite" or kind == "dao-favourite-remove") {
      let gid : Text = switch (Text.stripStart(target, #text "game:")) { case (?g) { g }; case null { return #err("Pick a Showroom game") } };
      switch (gameSubmissions.get(gid)) {
        case null { return #err("Game not found") };
        case (?g) {
          if (g.status != "live" or g.gameTier != "showroom") return #err("Only live Showroom games can be DAO Favourites");
          if (Principal.equal(g.creator, caller)) return #err("You can't propose your own game");
        };
      };
      if (kind == "dao-favourite") {
        if (isDaoCrowned(gid)) return #err("That game is already a DAO Favourite");
        if (crownedLiveCount() >= DAO_FAV_PROPOSAL_CAP) return #err("DAO Favourites are full for community proposals (10)");
      } else {
        if (not isDaoCrowned(gid)) return #err("That game isn't a DAO Favourite");
      };
      tgt := "game:" # gid;
    };
    if (kind == "mute-user") {
      let who = Principal.fromText(target); // malformed text traps and nothing is saved; the UI validates first
      if (isAdmin(who) or isModerator(who)) return #err("The Dev Team and moderators can't be targeted");
      if (Principal.equal(who, caller)) return #err("You can't target yourself");
      if (mutedUntil(who) > now) return #err("That user is already muted");
      let whoText = Principal.toText(who);
      for ((pid, m) in proposalMetaEntries.vals()) {
        if (m.kind == "mute-user" and m.target == whoText) {
          switch (findProposalById(pid)) {
            case (?pp) { if (pp.endsAt + MUTE_VOTE_COOLDOWN_NS > now) return #err("That user was the subject of a mute vote recently (7-day cooldown)") };
            case null {};
          };
        };
      };
      tgt := whoText;
    };
    if (kind == "content-removal") {
      let hid : Text = switch (Text.stripStart(target, #text "hole:")) { case (?h) { h }; case null { return #err("Pick a Blackhole entry") } };
      switch (findHoleSubmission(hid)) {
        case null { return #err("Blackhole entry not found") };
        case (?h) { if (h.status != "active") return #err("That Blackhole entry is no longer active") };
      };
      for ((_, m) in proposalMetaEntries.vals()) {
        if (m.kind == "content-removal" and m.target == "hole:" # hid and (m.execStatus == "none" or m.execStatus == "pending")) return #err("There's already an open removal vote for that entry");
      };
      tgt := "hole:" # hid;
    };
    if (kind != "bug-report" and not admin) {
      let tokenBal = getTokenBalance(caller);
      if (tokenBal < 5) return #err("Not enough tokens. Creating a proposal costs 5 Tokens. Have " # Nat.toText(tokenBal));
      tokens.put(caller, tokenBal - 5);
      daoTreasuryE8s += 5 * TOKEN_TIP_E8S_PER_TOKEN;
      daoInProposalsE8s += 5 * TOKEN_TIP_E8S_PER_TOKEN;
    };
    proposalCounter += 1;
    let proposal : Proposal = {
      id = "proposal-" # Nat.toText(proposalCounter);
      title = title;
      body = body;
      category = kind;
      official = admin;
      images = images;
      author = caller;
      authorName = Principal.toText(caller);
      createdAt = now;
      endsAt = now + durationToNs(duration);
      duration = duration;
      votesFor = 0;
      votesAgainst = 0;
      votes = [];
      discussion = [];
      closed = false;
    };
    proposalEntries := Array.append<Proposal>([proposal], proposalEntries);
    let finalChoices = Buffer.toArray(cleaned);
    putProposalMeta(proposal.id, {
      kind = kind;
      choices = finalChoices;
      choiceTotals = Array.tabulate<Nat>(finalChoices.size(), func(_ : Nat) : Nat { 0 });
      target = tgt;
      voterCount = 0;
      execStatus = "none";
      executeAfter = 0;
    });
    addDxp(caller, 10);
    #ok(proposal.id)
  };

  public query func getProposalMetas() : async [(Text, ProposalMeta)] { proposalMetaEntries };

  // === BINDING (CONTROLLING) PROPOSALS (stage 2) ===
  stable var bindingQuorum : Nat = 5;                         // PRE-MAINNET: keep at 5 (test tool can lower it)
  stable var bindingTimelockNs : Int = 86_400_000_000_000;    // PRE-MAINNET: keep at 24h
  func isBindingKind(k : Text) : Bool { k == "dao-favourite" or k == "dao-favourite-remove" or k == "mute-user" or k == "content-removal" };
  func findProposalById(id : Text) : ?Proposal {
    for (p in proposalEntries.vals()) { if (p.id == id) return ?p };
    null
  };
  func executeDaoFavouriteProposal(m : ProposalMeta) : Text {
    let gid : Text = switch (Text.stripStart(m.target, #text "game:")) { case (?g) { g }; case null { return "failed:bad-target" } };
    switch (gameSubmissions.get(gid)) {
      case null { return "failed:game-missing" };
      case (?g) { if (g.status != "live") return "failed:game-not-live" };
    };
    if (m.kind == "dao-favourite") {
      if (isDaoCrowned(gid)) return "failed:already-favourite";
      if (crownedLiveCount() >= DAO_FAV_PROPOSAL_CAP) return "failed:full";
      daoFavouriteGameIds := Array.append<Text>(daoFavouriteGameIds, [gid]);
      daoFavExcludedIds := Array.filter<Text>(daoFavExcludedIds, func(x) { x != gid });
      "executed"
    } else {
      if (not isDaoCrowned(gid)) return "failed:not-favourite";
      daoFavouriteGameIds := Array.filter<Text>(daoFavouriteGameIds, func(x) { x != gid });
      "executed"
    }
  };
  // Called by the 10-minute timer. Iterates a snapshot, so status updates mid-loop are safe.
  // === MUTES + CONTENT REMOVAL (stage 3) ===
  stable var userMuteEntries : [(Principal, Int)] = [];          // (user, muted until ns)
  transient let MUTE_DURATION_NS : Int = 604_800_000_000_000;     // 7 days
  transient let MUTE_VOTE_COOLDOWN_NS : Int = 604_800_000_000_000; // 7 days after a mute vote ends
  func mutedUntil(p : Principal) : Int {
    for ((q, t) in userMuteEntries.vals()) { if (Principal.equal(q, p)) return t };
    0
  };
  func setMute(p : Principal, until : Int) {
    let rest = Array.filter<(Principal, Int)>(userMuteEntries, func(e) { not Principal.equal(e.0, p) });
    userMuteEntries := if (until > 0) { Array.append<(Principal, Int)>(rest, [(p, until)]) } else { rest };
  };
  // Muting only blocks posting (forums, DAO, proposals, replies, Blackhole uploads) - never games, votes or anything else.
  func muteBlockMessage(p : Principal) : ?Text {
    if (isAdmin(p)) return null;
    if (mutedUntil(p) > Time.now()) ?"You're muted from posting after a community vote. You can still play games and use everything else." else null
  };
  public query func getMuteStatus(p : Principal) : async Int {
    let t = mutedUntil(p);
    if (t > Time.now()) t else 0
  };
  public shared(msg) func adminSetMute(p : Principal, days : Nat) : async Result.Result<Text, Text> {
    assert (not isBannedNow(msg.caller)); // banned: only withdrawals, claims and listing allowed
    if (not isAdmin(msg.caller)) return #err("Admin only");
    if (days == 0) { setMute(p, 0); return #ok("Unmuted") };
    if (days > 30) return #err("Mute length must be 1-30 days (0 to unmute)");
    setMute(p, Time.now() + days * 86_400_000_000_000);
    #ok("Muted for " # Nat.toText(days) # " day(s)")
  };
  public shared(msg) func adminRestoreHoleSubmission(id : Text) : async Result.Result<Text, Text> {
    assert (not isBannedNow(msg.caller)); // banned: only withdrawals, claims and listing allowed
    if (not isAdmin(msg.caller)) return #err("Admin only");
    switch (findHoleSubmission(id)) {
      case null { return #err("Submission not found") };
      case (?h) { if (h.status != "hidden") return #err("Only hidden entries can be restored") };
    };
    holeSubmissionEntries := Array.map<HoleSubmission, HoleSubmission>(holeSubmissionEntries, func(item) { if (item.id == id) { { item with status = "active" } } else { item } });
    #ok("Blackhole entry restored")
  };
  func executeBindingProposal(m : ProposalMeta) : Text {
    if (m.kind == "mute-user") {
      let who = Principal.fromText(m.target);
      if (isAdmin(who) or isModerator(who)) return "failed:protected";
      let until = Time.now() + MUTE_DURATION_NS;
      setMute(who, if (mutedUntil(who) > until) { mutedUntil(who) } else { until });
      return "executed";
    };
    if (m.kind == "content-removal") {
      let hid : Text = switch (Text.stripStart(m.target, #text "hole:")) { case (?h) { h }; case null { return "failed:bad-target" } };
      switch (findHoleSubmission(hid)) {
        case null { return "failed:entry-missing" };
        case (?h) { if (h.status != "active") return "failed:entry-gone" };
      };
      holeSubmissionEntries := Array.map<HoleSubmission, HoleSubmission>(holeSubmissionEntries, func(item) { if (item.id == hid) { { item with status = "hidden" } } else { item } });
      return "executed";
    };
    executeDaoFavouriteProposal(m)
  };
  func processBindingProposals() {
    let now = Time.now();
    for ((id, m) in proposalMetaEntries.vals()) {
      if (isBindingKind(m.kind)) {
        switch (findProposalById(id)) {
          case null {};
          case (?p) {
            if (m.execStatus == "none" and not proposalIsActive(p, now)) {
              if (m.voterCount < bindingQuorum) { putProposalMeta(id, { m with execStatus = "failed:quorum" }) }
              else if (p.votesFor <= p.votesAgainst) { putProposalMeta(id, { m with execStatus = "failed:rejected" }) }
              else { putProposalMeta(id, { m with execStatus = "pending"; executeAfter = now + bindingTimelockNs }) };
            } else if (m.execStatus == "pending" and now >= m.executeAfter) {
              putProposalMeta(id, { m with execStatus = executeBindingProposal(m) });
            };
          };
        };
      };
    };
  };
  func closeProposalWithStatus(proposalId : Text, status : Text) : Result.Result<Text, Text> {
    let meta = findProposalMeta(proposalId);
    switch (meta) { case (?m) { if (m.execStatus == "executed") return #err("Already executed; it can't be vetoed or closed") }; case null {} };
    var found = false;
    proposalEntries := Array.map<Proposal, Proposal>(proposalEntries, func(p) { if (p.id != proposalId) return p; found := true; { p with closed = true } });
    if (not found) return #err("Proposal not found");
    switch (meta) { case (?m) { putProposalMeta(proposalId, { m with execStatus = status }) }; case null {} };
    #ok("Proposal closed")
  };
  public shared(msg) func adminVetoProposal(proposalId : Text, reason : Text) : async Result.Result<Text, Text> {
    assert (not isBannedNow(msg.caller)); // banned: only withdrawals, claims and listing allowed
    if (not isAdmin(msg.caller)) return #err("Admin only");
    let r = if (Text.size(reason) > 200) { "vetoed" } else { "vetoed:" # reason };
    closeProposalWithStatus(proposalId, r)
  };
  // Admin: permanently delete a proposal (and its votes + meta). A deleted binding proposal can never execute.
  // No fee refund (the fee already went to the DAO treasury). Already-executed effects are not undone.
  public shared(msg) func adminDeleteProposal(proposalId : Text) : async Result.Result<Text, Text> {
    if (not isAdmin(msg.caller)) return #err("Admin only");
    let before = proposalEntries.size();
    proposalEntries := Array.filter<Proposal>(proposalEntries, func(p) { p.id != proposalId });
    if (proposalEntries.size() == before) return #err("Proposal not found");
    proposalMetaEntries := Array.filter<(Text, ProposalMeta)>(proposalMetaEntries, func(e) { e.0 != proposalId });
    importantProposalIds := Array.filter<Text>(importantProposalIds, func(x) { x != proposalId });
    #ok("Proposal deleted")
  };
  // Admin-flagged "important" proposals, shown to everyone in the Past Proposals popup.
  stable var importantProposalIds : [Text] = [];
  public shared(msg) func adminSetProposalImportant(proposalId : Text, on : Bool) : async Result.Result<Text, Text> {
    if (not isAdmin(msg.caller)) return #err("Admin only");
    let rest = Array.filter<Text>(importantProposalIds, func(x) { x != proposalId });
    if (on) {
      var exists = false;
      for (pr in proposalEntries.vals()) { if (pr.id == proposalId) { exists := true } };
      if (not exists) return #err("Proposal not found");
      importantProposalIds := Array.append<Text>(rest, [proposalId]);
      #ok("Marked important")
    } else {
      importantProposalIds := rest;
      #ok("Unmarked")
    }
  };
  public query func getImportantProposalIds() : async [Text] { importantProposalIds };
  public shared(msg) func closeProposal(proposalId : Text) : async Result.Result<Text, Text> {
    assert (not isBannedNow(msg.caller)); // banned: only withdrawals, claims and listing allowed
    if (not isAdmin(msg.caller)) return #err("Admin only");
    closeProposalWithStatus(proposalId, "closed")
  };
  // TESTING ONLY (lock before mainnet): lower quorum / timelock, and end a proposal's voting now.
  public shared(msg) func adminSetBindingTestMode(quorum : Nat, timelockMinutes : Nat) : async Result.Result<Text, Text> {
    assert (not isBannedNow(msg.caller)); // banned: only withdrawals, claims and listing allowed
    if (not isAdmin(msg.caller)) return #err("Admin only");
    if (quorum < 1 or quorum > 50) return #err("Quorum must be 1-50");
    if (timelockMinutes > 10_080) return #err("Timelock must be 0-10080 minutes");
    bindingQuorum := quorum;
    bindingTimelockNs := timelockMinutes * 60_000_000_000;
    #ok("Binding proposals: quorum " # Nat.toText(quorum) # ", timelock " # Nat.toText(timelockMinutes) # " min")
  };
  public shared(msg) func adminTestEndProposalVoting(proposalId : Text) : async Result.Result<Text, Text> {
    assert (not isBannedNow(msg.caller)); // banned: only withdrawals, claims and listing allowed
    if (not isAdmin(msg.caller)) return #err("Admin only");
    var found = false;
    let now = Time.now();
    proposalEntries := Array.map<Proposal, Proposal>(proposalEntries, func(p) { if (p.id != proposalId) return p; found := true; { p with endsAt = now } });
    if (not found) return #err("Proposal not found");
    processBindingProposals();
    #ok("Voting ended; result evaluated")
  };
  public query func getBindingSettings() : async { quorum : Nat; timelockNs : Int; crownedCount : Nat; proposalCap : Nat; totalCap : Nat } {
    { quorum = bindingQuorum; timelockNs = bindingTimelockNs; crownedCount = crownedLiveCount(); proposalCap = DAO_FAV_PROPOSAL_CAP; totalCap = DAO_FAV_BACK_TOP_N }
  };

  public shared(msg) func castVote(proposalId : Text, vote : Text) : async Result.Result<Text, Text> {
    assert (not isBannedNow(msg.caller)); // banned: only withdrawals, claims and listing allowed
    if (isAnonymousPrincipal(msg.caller)) return #err("Connect wallet to vote");
    let meta = findProposalMeta(proposalId);
    let isMulti = switch (meta) { case (?m) { m.choices.size() > 0 }; case null { false } };
    let choiceIdx : ?Nat = switch (meta) { case (?m) { if (m.choices.size() > 0) { parseChoiceVote(vote, m.choices.size()) } else { null } }; case null { null } };
    if (isMulti) { if (choiceIdx == null) return #err("Pick one of the proposal's choices") }
    else { if (vote != "for" and vote != "against") return #err("Vote must be for or against") };
    let weight = votingPowerOf(msg.caller);
    if (weight == 0 and not isAdmin(msg.caller)) return #err("Voting Power Badge required to vote");
    var found = false;
    var rejected : ?Text = null;
    proposalEntries := Array.map<Proposal, Proposal>(proposalEntries, func(proposal) {
      if (proposal.id != proposalId) return proposal;
      found := true;
      if (not proposalIsActive(proposal, Time.now())) {
        rejected := ?"Proposal is not active";
        return proposal;
      };
      for (existingVote in proposal.votes.vals()) {
        if (Principal.equal(existingVote.voter, msg.caller)) {
          rejected := ?"Already voted";
          return proposal;
        };
      };
      let effectiveWeight = if (isAdmin(msg.caller)) 0 else weight; // admin votes are recorded and visible but carry zero weight
      let newVote : ProposalVote = { voter = msg.caller; vote = vote; weight = effectiveWeight; timestamp = Time.now() };
      {
        id = proposal.id;
        title = proposal.title;
        body = proposal.body;
        category = proposal.category;
        official = proposal.official;
        images = proposal.images;
        author = proposal.author;
        authorName = proposal.authorName;
        createdAt = proposal.createdAt;
        endsAt = proposal.endsAt;
        duration = proposal.duration;
        votesFor = proposal.votesFor + (if (vote == "for") effectiveWeight else 0);
        votesAgainst = proposal.votesAgainst + (if (vote == "against") effectiveWeight else 0);
        votes = Array.append<ProposalVote>(proposal.votes, [newVote]);
        discussion = proposal.discussion;
        closed = proposal.closed;
      }
    });
    switch (rejected) { case (?reason) { return #err(reason) }; case null {} };
    if (not found) return #err("Proposal not found");
    switch (meta) {
      case (?m) {
        let ew : Nat = if (isAdmin(msg.caller)) 0 else weight;
        let totals = Array.tabulate<Nat>(m.choiceTotals.size(), func(i : Nat) : Nat { m.choiceTotals[i] + (switch (choiceIdx) { case (?c) { if (c == i) ew else 0 }; case null { 0 } }) });
        putProposalMeta(proposalId, { m with choiceTotals = totals; voterCount = m.voterCount + (if (ew > 0) 1 else 0) });
      };
      case null {};
    };
    if (weight > 0) { addDxp(msg.caller, weight) };
    #ok("Vote recorded")
  };

  public shared(msg) func addProposalReply(proposalId : Text, body : Text) : async Result.Result<Text, Text> {
    assert (not isBannedNow(msg.caller)); // banned: only withdrawals, claims and listing allowed
    if (isAnonymousPrincipal(msg.caller)) return #err("Connect wallet to reply");
    switch (muteBlockMessage(msg.caller)) { case (?m) { return #err(m) }; case null {} };
    if (votingPowerOf(msg.caller) == 0 and not isAdmin(msg.caller)) return #err("Voting Power Badge required for proposal discussion");
    if (Text.size(Text.trim(body, #char ' ')) == 0) return #err("Reply required");
    var found = false;
    proposalEntries := Array.map<Proposal, Proposal>(proposalEntries, func(proposal) {
      if (proposal.id != proposalId) return proposal;
      found := true;
      let reply : ProposalDiscussion = { author = msg.caller; authorName = Principal.toText(msg.caller); body = body; timestamp = Time.now() };
      {
        id = proposal.id; title = proposal.title; body = proposal.body; category = proposal.category; official = proposal.official; images = proposal.images; author = proposal.author; authorName = proposal.authorName; createdAt = proposal.createdAt; endsAt = proposal.endsAt; duration = proposal.duration; votesFor = proposal.votesFor; votesAgainst = proposal.votesAgainst; votes = proposal.votes; discussion = Array.append<ProposalDiscussion>(proposal.discussion, [reply]); closed = proposal.closed;
      }
    });
    if (not found) return #err("Proposal not found");
    #ok("Reply added")
  };

  public query func getProposals() : async [Proposal] { proposalEntries };

  public query func getProposal(proposalId : Text) : async ?Proposal {
    for (proposal in proposalEntries.vals()) {
      if (proposal.id == proposalId) return ?proposal;
    };
    null
  };

  public query func daoStats() : async DaoStats {
    var active : Nat = 0;
    let now = Time.now();
    for (proposal in proposalEntries.vals()) {
      if (proposalIsActive(proposal, now)) active += 1;
    };
    { proposals = proposalEntries.size(); activeProposals = active; badgeHolders = gamerBadgeEntries.size(); forumThreads = forumThreadEntries.size() }
  };

  // === HEALTH CHECK ===
  public query func whoami() : async Principal {
    Principal.fromActor(ArcadeBackend);
  };

  public query func stats() : async {
    totalPlayers : Nat;
    totalRedemptions : Nat;
    defaultTicketCost : Nat;
    totalNftListings : Nat;
    totalGameSubmissions : Nat;
    totalRevenueIcp : Nat;
  } {
    {
      totalPlayers = if (runtimeStateHydrated) tickets.size() else ticketEntries.size();
      totalRedemptions = redemptionLog.size();
      defaultTicketCost = defaultCost;
      totalNftListings = if (runtimeStateHydrated) nftListings.size() else nftListingEntries.size();
      totalGameSubmissions = if (runtimeStateHydrated) gameSubmissions.size() else gameSubmissionEntries.size();
      totalRevenueIcp = totalRevenueE8s / 100_000_000;
    };
  };

  // Lottery timer: placed LAST so every function it uses is already defined when it starts.
  // Re-armed automatically on every install/upgrade (transient fields re-initialise in a persistent actor).
  transient let _lotteryTimerId : Timer.TimerId = Timer.recurringTimer<system>(#seconds 600, lotteryTick);
  transient let _autoPayoutTimerId : Timer.TimerId = Timer.recurringTimer<system>(#seconds 3600, autoPayoutTick); // after everything it uses (ledger, hex helpers)
};
