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
import Option "mo:base/Option";
import Bool "mo:base/Bool";
import Blob "mo:base/Blob";
import Char "mo:base/Char";
import Nat8 "mo:base/Nat8";

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

  // === EXT v2 STANDARD TYPES ===
  type ExtUser = { #principal : Principal; #address : Text };
  type ExtTransferRequest = {
    from : ExtUser;
    to : ExtUser;
    token : Text; // TokenIdentifier
    amount : Nat;
    memo : Blob;
    notify : Bool;
    subaccount : ?[Nat8];
  };
  type ExtTransferResponse = {
    #ok : Nat;
    #err : {
      #Unauthorized : Text;
      #InsufficientBalance;
      #Rejected;
      #InvalidToken : Text;
      #CannotNotify : Text;
      #Other : Text;
    };
  };
  type ExtBearerResponse = {
    #ok : Text; // AccountIdentifier
    #err : { #InvalidToken : Text; #Other : Text };
  };

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
    standard : Text; // "ext" or "icrc7"
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
    gameTier : Text; // "backroom", "showroom", "showroom-pending", "jays-picks"
    status : Text; // "live", "removed"
    feePaid : Nat; // in e8s
    showroomFeePaid : Nat; // in e8s
    txId : Nat;
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
  transient let TREASURY_SAFETY_BUFFER_E8S : Nat = 10_000;

  func ticketCostToSellerPayoutE8s(ticketCost : Nat) : Nat {
    ticketCost * TICKET_LIABILITY_E8S;
  };

  // === REVENUE SPLIT CONSTANTS (Economy v5) ===
  // Ticket games: 20% to game dev, 70% to game ticket pool, 5% DAO gaming rewards, 5% burn.
  transient let TICKET_GAME_CREATOR_SHARE : Nat = 20; // percent
  transient let TICKET_GAME_DAO_SHARE : Nat = 5; // percent
  transient let TICKET_GAME_BURN_SHARE : Nat = 5; // percent
  transient let TICKET_GAME_POOL_SHARE : Nat = 70; // percent
  // Regular/non-ticket games: 80% to game dev, 10% DAO gaming rewards, 10% burn.
  transient let REGULAR_GAME_CREATOR_SHARE : Nat = 80; // percent
  transient let REGULAR_GAME_DAO_SHARE : Nat = 10; // percent
  transient let REGULAR_GAME_BURN_SHARE : Nat = 10; // percent
  // NFT sales: 90% to NFT creator, 10% stays in operating treasury; not DAO jackpot or member reward funding.
  transient let NFT_CREATOR_SHARE : Nat = 90; // percent

  // NFT listing fee: 2 Tokens = 0.02 ICP equivalent at the fixed 1 ICP = 100 Tokens rate.
  transient let NFT_LISTING_FEE_TOKENS : Nat = 2;
  transient let NFT_LISTING_FEE_E8S : Nat = NFT_LISTING_FEE_TOKENS * TOKEN_LIABILITY_E8S;

  // Backend canister's own account identifier (for EXT bearer verification).
  // This must match the default EXT AccountIdentifier for pifyq-raaaa-aaaab-agrqq-cai.
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

  func arcadeExtAccountId() : Text {
    SELF_ACCOUNT_ID
  };

  func extHoldMismatchMessage(accountId : Text) : Text {
    "Arcade does not hold this EXT NFT. Bearer: " # accountId # ". Expected/current arcade account: " # arcadeExtAccountId() # ". Backend principal: " # Principal.toText(Principal.fromActor(ArcadeBackend))
  };

  // Create dynamic EXT actor for any canister
  func getExtActor(canisterId : Text) : actor {
    bearer : shared query (Text) -> async ExtBearerResponse;
    transfer : shared (ExtTransferRequest) -> async ExtTransferResponse;
  } {
    actor(canisterId);
  };

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

  // New (v2) - Revenue log
  stable var revenueLogEntries : [RevenueEvent] = [];

  // New (v2) - Legacy game creator royalty balances (ICP e8s).
  // Phase 2 keeps this stable shape for migration compatibility and treats it as game creator earnings.
  stable var royaltyEntries : [(Principal, Nat)] = [];

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
  transient var nftSellerEarningsE8s = HashMap.HashMap<Principal, Nat>(16, Principal.equal, Principal.hash);
  transient var refundsE8s = HashMap.HashMap<Principal, Nat>(16, Principal.equal, Principal.hash);
  transient var escrows = HashMap.HashMap<Text, EscrowedNft>(16, Text.equal, textHash);
  transient var gameRawTicketPools = HashMap.HashMap<Text, Nat>(16, Text.equal, textHash);
  transient var gameBackedTicketPools = HashMap.HashMap<Text, Nat>(16, Text.equal, textHash);
  transient var paidGameSessions = HashMap.HashMap<Text, PaidGameSession>(16, Text.equal, textHash);
  transient var gamePayoutConfigs = HashMap.HashMap<Text, GamePayoutConfig>(16, Text.equal, textHash);
  transient var gameTicketJackpotConfigs = HashMap.HashMap<Text, GameTicketJackpotConfig>(16, Text.equal, textHash);
  transient var tipReceipts = Buffer.Buffer<TipReceipt>(0);
  transient var runtimeStateHydrated = false;

  // ICP ledger fee-sized floor: claiming less than this creates dust-level
  // payouts that are not worth moving before real volume starts.
  transient let ROYALTY_CLAIM_MIN_E8S : Nat = 10_000;
  transient let ICP_LEDGER_FEE_E8S : Nat = 10_000;
  transient let ICP_TIP_MIN_E8S : Nat = 10_000;
  transient var operatingTreasuryWithdrawalInFlight = false;

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
      nftSellerEarningEntries := Iter.toArray(nftSellerEarningsE8s.entries());
      refundEntries := Iter.toArray(refundsE8s.entries());
      escrowEntries := Iter.toArray(escrows.entries());
      gameRawTicketPoolEntries := Iter.toArray(gameRawTicketPools.entries());
      gameBackedTicketPoolEntries := Iter.toArray(gameBackedTicketPools.entries());
      paidGameSessionEntries := Iter.toArray(paidGameSessions.entries());
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
    nftSellerEarningsE8s := HashMap.fromIter<Principal, Nat>(nftSellerEarningEntries.vals(), nftSellerEarningEntries.size(), Principal.equal, Principal.hash);
    refundsE8s := HashMap.fromIter<Principal, Nat>(refundEntries.vals(), refundEntries.size(), Principal.equal, Principal.hash);
    escrows := HashMap.fromIter<Text, EscrowedNft>(escrowEntries.vals(), escrowEntries.size(), Text.equal, textHash);
    gameRawTicketPools := HashMap.fromIter<Text, Nat>(gameRawTicketPoolEntries.vals(), gameRawTicketPoolEntries.size(), Text.equal, textHash);
    gameBackedTicketPools := HashMap.fromIter<Text, Nat>(gameBackedTicketPoolEntries.vals(), gameBackedTicketPoolEntries.size(), Text.equal, textHash);
    paidGameSessions := HashMap.fromIter<Text, PaidGameSession>(paidGameSessionEntries.vals(), paidGameSessionEntries.size(), Text.equal, textHash);
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
    runtimeStateHydrated := true;
  };

  // === HELPERS ===
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
    let newGxp = getGxpBalance(player) + amount;
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
    let newDxp = getDxpBalance(player) + amount;
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
    let newMxp = getMxpBalance(player) + amount;
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

  func getOpenPaidGameSession(player : Principal, gameId : Text) : ?PaidGameSession {
    switch (paidGameSessions.get(paidGameSessionKey(player, gameId))) {
      case null null;
      case (?session) { if (session.open) ?session else null };
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

  func creditRefundE8s(creator : Principal, amountE8s : Nat) {
    let current = getRefundBalance(creator);
    refundsE8s.put(creator, current + amountE8s);
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

  func isTicketGameSubmission(game : GameSubmission) : Bool {
    isTicketGameTier(game.gameTier);
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
        if (game.status == "live" and isTicketGameTier(game.gameTier)) {
          ticketGameCount += 1;
          totalRawTicketPool += getGameRawTicketPoolValue(gameId);
          totalBackedTicketPool += getGameBackedTicketPoolValue(gameId);
        };
      };
    } else {
      for ((gameId, game) in gameSubmissionEntries.vals()) {
        if (game.status == "live" and isTicketGameTier(game.gameTier)) {
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

    for ((gameId, rawPool) in gameRawTicketPoolEntries.vals()) {
      switch (gameSubmissions.get(gameId)) {
        case (?game) {
          if (game.status == "live" and isTicketGameTier(game.gameTier)) {
            migratedRawPools.put(gameId, rawPool);
          };
        };
        case null {};
      };
    };

    // Public/backed truth is one-way explicit. Never infer backed balances from
    // legacy raw counters, because that would leak pre-separation state into the
    // public liability surface after upgrade.
    for ((gameId, backedPool) in gameBackedTicketPoolEntries.vals()) {
      switch (gameSubmissions.get(gameId)) {
        case (?game) {
          if (game.status == "live" and isTicketGameTier(game.gameTier)) {
            let rawPool = switch (migratedRawPools.get(gameId)) { case (?value) value; case null 0 };
            let sanitizedBackedPool = if (backedPool > rawPool) rawPool else backedPool;
            migratedBackedPools.put(gameId, sanitizedBackedPool);
          };
        };
        case null {};
      };
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
    // ticket credit: 70% of the ICP-equivalent lane, or 7 tickets per token at the
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
      abilities = collectionAbilitiesForIds(collection.nftIds);
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
    let caller = msg.caller;
    if (Principal.isAnonymous(caller)) return #err("Must be authenticated");
    hydrateRuntimeStateIfNeeded();
    if (amount == 0) return #err("Amount must be greater than zero");
    if (isBlankText(gameId)) return #err("Game ID is required");
    switch (getOpenPaidGameSession(caller, gameId)) {
      case (?_) { return #err("Session already open") };
      case null {};
    };
    let balance = getTokenBalance(caller);
    if (balance < amount) return #err("Not enough tokens. Have " # Nat.toText(balance) # " need " # Nat.toText(amount));

    switch (gameSubmissions.get(gameId)) {
      case null { return #err("Game not found: " # gameId) };
      case (?game) {
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

        let icpValueE8s : Nat = amount * 1_000_000;
        let creatorShare = if (isTicketGame) TICKET_GAME_CREATOR_SHARE else REGULAR_GAME_CREATOR_SHARE;
        let creatorShareE8s : Nat = (icpValueE8s * creatorShare) / 100;
        let currentRoyalty = getRoyaltyBalance(game.creator);
        royalties.put(game.creator, currentRoyalty + creatorShareE8s);

        logRevenue("gameplay", icpValueE8s, caller, 3);
        openPaidGameSession(caller, gameId, amount);
        #ok(newBal);
      };
    };
  };

  /// Win tickets from a game
  public shared(msg) func winTickets(amount : Nat) : async Result.Result<Nat, Text> {
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
  transient let MAX_TICKETS_PER_ROUND : Nat = 6;
  transient let JACKPOT_MAX_TICKETS_PER_WIN : Nat = 25;
  transient let JACKPOT_POOL_BASIS_POINTS : Nat = 1000; // 10% of remaining backed pool
  transient let JACKPOT_POOL_PERCENT : Nat = JACKPOT_POOL_BASIS_POINTS / 100; // v1 compatibility default = 10%

  func getDayStart() : Int {
    let now = Time.now();
    // Rough day boundary: round down to nearest 86400 seconds
    now - (now % 86_400_000_000_000);
  };

  func getPlaysInLastHour(player : Principal) : Nat {
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
    if (thresholds.size() != 7) {
      return #err("Exactly 7 score thresholds are required");
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
    if (not config.enabled or config.thresholds.size() != 7) {
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
    if (level > 6) { 6 } else { level };
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

  func ticketJackpotTierPayout(tierLabel : Text, percent : Nat, remainingBackedAfterBase : Nat) : TicketJackpotTierPayout {
    {
      tierLabel = tierLabel;
      percent = percent;
      uncappedTickets = remainingBackedAfterBase * percent / 100;
    };
  };

  func capTicketJackpotPayout(uncappedTickets : Nat, remainingBackedAfterBase : Nat, remainingDailyAfterBase : Nat) : Nat {
    minNat(
      uncappedTickets,
      minNat(minNat(remainingBackedAfterBase, remainingDailyAfterBase), JACKPOT_MAX_TICKETS_PER_WIN),
    );
  };

  func calculateTicketJackpotPayout(config : GameTicketJackpotConfig, score : Nat, newRecord : Bool, remainingBackedAfterBase : Nat, remainingDailyAfterBase : Nat) : TicketJackpotCalculation {
    if (not config.enabled or remainingBackedAfterBase == 0 or remainingDailyAfterBase == 0) {
      return emptyTicketJackpotCalculation();
    };

    let labels = Buffer.Buffer<Text>(3);
    let payouts = Buffer.Buffer<TicketJackpotTierPayout>(3);
    var uncappedTotal : Nat = 0;

    if (config.highPayoutPercent > 0 and score >= config.highScoreThreshold) {
      let tier = ticketJackpotTierPayout("high", config.highPayoutPercent, remainingBackedAfterBase);
      labels.add("high");
      payouts.add(tier);
      uncappedTotal += tier.uncappedTickets;
    } else if (score >= config.lowScoreThreshold and config.lowPayoutPercent > 0) {
      let tier = ticketJackpotTierPayout("low", config.lowPayoutPercent, remainingBackedAfterBase);
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
      payouts = payoutLevels();
      updatedAt = config.updatedAt;
    };
  };

  /// Admin: set or update one game's 7-level ticket payout ladder.
  /// Level 1 pays 0 tickets, level 7 pays 6 tickets; thresholds are minimum scores.
  public shared(msg) func setGamePayoutConfig(gameId : Text, enabled : Bool, thresholds : [Nat]) : async Result.Result<GamePayoutConfigView, Text> {
    if (not isAdmin(msg.caller)) return #err("Not authorized");
    hydrateRuntimeStateIfNeeded();
    if (isBlankText(gameId)) return #err("Game ID is required");
    switch (gameSubmissions.get(gameId)) {
      case null { return #err("Game not found: " # gameId) };
      case (?game) {
        if (not isTicketGameTier(game.gameTier)) {
          return #err("Game is not ticket-backed: " # gameId);
        };
      };
    };
    if (thresholds.size() != 7) {
      return #err("Exactly 7 score thresholds are required");
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
      lowPayoutPercent = JACKPOT_POOL_PERCENT;
      highScoreThreshold = 0;
      highPayoutPercent = 0;
      newHighScorePayoutPercent = JACKPOT_POOL_PERCENT;
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
    if (not isAdmin(msg.caller)) return #err("Not authorized");
    hydrateRuntimeStateIfNeeded();
    if (Text.size(gameId) == 0) return #err("Game id is required");
    switch (gameSubmissions.get(gameId)) {
      case null { return #err("Unknown game: " # gameId) };
      case (?game) {
        if (game.status != "live") {
          return #err("Game must be live/submitted before ticket jackpot configuration: " # gameId);
        };
        if (not isTicketGameTier(game.gameTier)) {
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
  public shared(msg) func submitGameScore(
    gameId : Text,
    score : Nat,
    tokenCost : Nat,
    inputHash : Text,
    durationMs : Nat
  ) : async Result.Result<{ tickets : Nat; baseTickets : Nat; jackpotTickets : Nat; newRecord : Bool; jackpotTierLabels : [Text]; jackpotUncappedTickets : Nat; jackpotCapped : Bool; jackpotPoolRemaining : Nat; tokenBalance : Nat; ticketBalance : Nat }, Text> {
    let caller = msg.caller;
    if (Principal.isAnonymous(caller)) return #err("Must be authenticated");
    hydrateRuntimeStateIfNeeded();
    if (isBlankText(gameId)) return #err("Game ID is required");

    let game = switch (gameSubmissions.get(gameId)) {
      case null { return #err("Game not found: " # gameId) };
      case (?value) { value };
    };

    if (game.status != "live") return #err("Game is not live: " # gameId);
    if (not isTicketGameTier(game.gameTier)) return #err("Game is not ticket-backed: " # gameId);

    let session = switch (getOpenPaidGameSession(caller, gameId)) {
      case null { return #err("No active paid session") };
      case (?value) { value };
    };
    if (tokenCost != session.tokenCost) {
      return #err("Token cost does not match active session");
    };

    let now = Time.now();

    // CHECK 1: Cooldown (30 seconds between plays)
    let lastPlay = getLastPlayTime(caller);
    if (lastPlay > 0 and (now - lastPlay) < COOLDOWN_NS) {
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
    playLog.add((caller, now));
    let totalPlays = getTotalPlays(caller);
    accountPlayCount.put(caller, totalPlays + 1);

    // CHECK 4: Calculate tickets from the admin-calibrated per-game payout table.
    // Missing or disabled config is explicit calibration-off mode and pays 0.
    var ticketPayout : Nat = switch (gamePayoutConfigs.get(gameId)) {
      case null 0;
      case (?config) calculateConfiguredTicketPayout(score, config);
    };

    // CHECK 5: Hard cap normal payouts at 6 tickets for payout-system v1.
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
    let newRecord = recordValidatedHighScore(caller, gameId, score);
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
          calculateTicketJackpotPayout(config, score, newRecord, remainingBackedAfterBase, remainingDailyAfterBase);
        } else {
          emptyTicketJackpotCalculation();
        };
      };
    };
    let jackpotTickets : Nat = jackpotCalculation.tickets;
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
    let resultLog = Buffer.fromArray<GameResult>(gameResultLog);
    resultLog.add({ gameId = gameId; score = score; ticketsEarned = totalTicketPayout; inputHash = inputHash; durationMs = durationMs });
    gameResultLog := Buffer.toArray(resultLog);

    #ok({
      tickets = totalTicketPayout;
      baseTickets = baseTickets;
      jackpotTickets = jackpotTickets;
      newRecord = newRecord;
      jackpotTierLabels = jackpotCalculation.tierLabels;
      jackpotUncappedTickets = jackpotCalculation.uncappedTickets;
      jackpotCapped = jackpotCalculation.capped;
      jackpotPoolRemaining = getGameBackedTicketPoolValue(gameId);
      tokenBalance = getTokenBalance(caller);
      ticketBalance = getTicketBalance(caller);
    });
  };

  /// Force-close an open paid game session without ticket payout.
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
      feePaid = NFT_LISTING_FEE_E8S; // 2 Tokens = 0.02 ICP equivalent
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

  /// Apply for NFT Showroom (existing = instant 1 ICP, minted = 5 ICP escrow)
  public shared(msg) func applyNftShowroom(listingId : Text, feeTxId : Nat) : async Result.Result<Text, Text> {
    let caller = msg.caller;
    hydrateRuntimeStateIfNeeded();
    switch (nftListings.get(listingId)) {
      case null { return #err("Listing not found") };
      case (?listing) {
        if (not Principal.equal(listing.creator, caller) and not isAdmin(caller)) return #err("Not the listing owner");
        if (listing.tier == "showroom" or listing.tier == "jays-picks") return #err("Already in Showroom or Jay's Picks");

        if (listing.listingType == "existing") {
          // Auto-approve, 1 ICP
          let updated : NftListing = {
            id = listing.id; listingType = listing.listingType; name = listing.name;
            description = listing.description; rarity = listing.rarity; ticketCost = listing.ticketCost;
            imageUrl = listing.imageUrl; creator = listing.creator;
            tier = "showroom"; status = listing.status;
            feePaid = listing.feePaid; showroomFeePaid = 100_000_000; // 1 ICP
            txId = listing.txId; createdAt = listing.createdAt;
            sourceCanisterId = listing.sourceCanisterId; sourceTokenId = listing.sourceTokenId;
            sourceTokenKey = listing.sourceTokenKey; collectionName = listing.collectionName;
          };
          nftListings.put(listingId, updated);
          logRevenue("nft-showroom", 100_000_000, caller, 3);
          #ok("Showroom approved! Your NFT is now featured.");
        } else {
          // Minted: needs admin approval, 5 ICP escrow
          let updated : NftListing = {
            id = listing.id; listingType = listing.listingType; name = listing.name;
            description = listing.description; rarity = listing.rarity; ticketCost = listing.ticketCost;
            imageUrl = listing.imageUrl; creator = listing.creator;
            tier = "showroom-pending"; status = listing.status;
            feePaid = listing.feePaid; showroomFeePaid = 500_000_000; // 5 ICP
            txId = listing.txId; createdAt = listing.createdAt;
            sourceCanisterId = listing.sourceCanisterId; sourceTokenId = listing.sourceTokenId;
            sourceTokenKey = listing.sourceTokenKey; collectionName = listing.collectionName;
          };
          nftListings.put(listingId, updated);
          #ok("Showroom application submitted! Awaiting admin approval.");
        };
      };
    };
  };

  /// Admin: approve NFT showroom application
  public shared(msg) func approveNftShowroom(listingId : Text) : async Result.Result<Text, Text> {
    if (not isAdmin(msg.caller)) return #err("Not authorized");
    hydrateRuntimeStateIfNeeded();
    switch (nftListings.get(listingId)) {
      case null { return #err("Listing not found") };
      case (?listing) {
        if (listing.tier != "showroom-pending") return #err("Not pending showroom approval");
        let updated : NftListing = {
          id = listing.id; listingType = listing.listingType; name = listing.name;
          description = listing.description; rarity = listing.rarity; ticketCost = listing.ticketCost;
          imageUrl = listing.imageUrl; creator = listing.creator;
          tier = "showroom"; status = listing.status;
          feePaid = listing.feePaid; showroomFeePaid = listing.showroomFeePaid;
          txId = listing.txId; createdAt = listing.createdAt;
          sourceCanisterId = listing.sourceCanisterId; sourceTokenId = listing.sourceTokenId;
          sourceTokenKey = listing.sourceTokenKey; collectionName = listing.collectionName;
        };
        nftListings.put(listingId, updated);
        logRevenue("nft-showroom", listing.showroomFeePaid, listing.creator, 3);
        #ok("NFT approved for Showroom!");
      };
    };
  };

  /// Admin: reject NFT showroom application (refund 4 ICP, keep 1 ICP)
  public shared(msg) func rejectNftShowroom(listingId : Text) : async Result.Result<Text, Text> {
    if (not isAdmin(msg.caller)) return #err("Not authorized");
    hydrateRuntimeStateIfNeeded();
    switch (nftListings.get(listingId)) {
      case null { return #err("Listing not found") };
      case (?listing) {
        if (listing.tier != "showroom-pending") return #err("Not pending showroom approval");
        let updated : NftListing = {
          id = listing.id; listingType = listing.listingType; name = listing.name;
          description = listing.description; rarity = listing.rarity; ticketCost = listing.ticketCost;
          imageUrl = listing.imageUrl; creator = listing.creator;
          tier = "open"; status = listing.status;
          feePaid = listing.feePaid; showroomFeePaid = 0;
          txId = listing.txId; createdAt = listing.createdAt;
          sourceCanisterId = listing.sourceCanisterId; sourceTokenId = listing.sourceTokenId;
          sourceTokenKey = listing.sourceTokenKey; collectionName = listing.collectionName;
        };
        nftListings.put(listingId, updated);
        // Keep 1 ICP (100_000_000 e8s), refund 4 ICP via the separate refund balance.
        let refundAmount = 400_000_000; // 4 ICP
        creditRefundE8s(listing.creator, refundAmount);
        logRevenue("nft-showroom", 100_000_000, listing.creator, 3); // keep 1 ICP
        #ok("NFT showroom application rejected. 4 ICP refund credited.");
      };
    };
  };

  /// Admin: promote to Jay's Picks
  public shared(msg) func promoteNftToJaysPicks(listingId : Text) : async Result.Result<Text, Text> {
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
    await adminDeleteCollection(collectionId);
  };

  /// Get token ability assignments for one official collection.
  public query func adminGetCollectionTokenAbilities(collectionId : Text) : async [(Nat, Text)] {
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

  public shared(msg) func adminDisableAbility(ability : Text) : async Result.Result<Text, Text> {
    if (not isAdmin(msg.caller)) return #err("Not authorized");
    hydrateRuntimeStateIfNeeded();
    disabledAbilities.put(ability, true);
    #ok("Ability disabled");
  };

  public shared(msg) func adminEnableAbility(ability : Text) : async Result.Result<Text, Text> {
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
  public shared(msg) func setPlayerProfile(name : Text, avatarUrl : Text, bio : Text) : async Result.Result<Text, Text> {
    if (Principal.isAnonymous(msg.caller)) return #err("Must be authenticated");
    hydrateRuntimeStateIfNeeded();
    let now = Time.now();
    let createdAt = switch (getPlayerProfileOpt(msg.caller)) { case (?existing) existing.createdAt; case null now };
    let profile : PlayerProfile = { name = name; avatarUrl = avatarUrl; bio = bio; createdAt = createdAt; lastSeen = now };
    playerProfiles.put(msg.caller, profile);
    #ok("Profile saved");
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
  public shared(msg) func submitGame(
    name : Text,
    developer : Text,
    url : Text,
    thumbnailUrl : Text,
    description : Text,
    compatibility : Text,
    feeTxId : Nat
  ) : async Result.Result<Text, Text> {
    let caller = msg.caller;
    if (Principal.isAnonymous(caller)) return #err("Must be authenticated");
    hydrateRuntimeStateIfNeeded();
    if (Text.size(name) == 0) return #err("Name required");
    if (Text.size(url) == 0) return #err("URL required");

    let id = genGameId();
    let game : GameSubmission = {
      id = id;
      name = name;
      developer = developer;
      url = url;
      thumbnailUrl = thumbnailUrl;
      description = description;
      compatibility = compatibility;
      creator = caller;
      gameTier = "backroom";
      status = "live";
      feePaid = 10_000_000_000; // 10 ICP
      showroomFeePaid = 0;
      txId = feeTxId;
      createdAt = Time.now();
    };
    gameSubmissions.put(id, game);
    logRevenue("game-backroom", 10_000_000_000, caller, 4);
    #ok(id);
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
      } else if (gameTier == "showroom-pending") {
        "showroom-pending";
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
    if (not isAdmin(msg.caller)) return [];
    hydrateRuntimeStateIfNeeded();
    Iter.toArray(gameSubmissions.vals());
  };

  /// Apply for Game Showroom (100 ICP escrow)
  public shared(msg) func applyGameShowroom(gameId : Text, feeTxId : Nat) : async Result.Result<Text, Text> {
    let caller = msg.caller;
    hydrateRuntimeStateIfNeeded();
    switch (gameSubmissions.get(gameId)) {
      case null { return #err("Game not found") };
      case (?game) {
        if (not Principal.equal(game.creator, caller) and not isAdmin(caller)) return #err("Not the game owner");
        if (game.gameTier == "showroom" or game.gameTier == "jays-picks") return #err("Already in Showroom or Jay's Picks");

        let updated : GameSubmission = {
          id = game.id; name = game.name; developer = game.developer;
          url = game.url; thumbnailUrl = game.thumbnailUrl; description = game.description;
          compatibility = game.compatibility; creator = game.creator;
          gameTier = "showroom-pending"; status = game.status;
          feePaid = game.feePaid; showroomFeePaid = 100_000_000_000; // 100 ICP
          txId = game.txId; createdAt = game.createdAt;
        };
        gameSubmissions.put(gameId, updated);
        #ok("Showroom application submitted! Awaiting admin approval.");
      };
    };
  };

  /// Admin: approve game showroom
  public shared(msg) func approveGameShowroom(gameId : Text) : async Result.Result<Text, Text> {
    if (not isAdmin(msg.caller)) return #err("Not authorized");
    hydrateRuntimeStateIfNeeded();
    switch (gameSubmissions.get(gameId)) {
      case null { return #err("Game not found") };
      case (?game) {
        if (game.gameTier != "showroom-pending") return #err("Not pending showroom approval");
        let updated : GameSubmission = {
          id = game.id; name = game.name; developer = game.developer;
          url = game.url; thumbnailUrl = game.thumbnailUrl; description = game.description;
          compatibility = game.compatibility; creator = game.creator;
          gameTier = "showroom"; status = game.status;
          feePaid = game.feePaid; showroomFeePaid = game.showroomFeePaid;
          txId = game.txId; createdAt = game.createdAt;
        };
        gameSubmissions.put(gameId, updated);
        logRevenue("game-showroom", game.showroomFeePaid, game.creator, 5);
        #ok("Game approved for Showroom!");
      };
    };
  };

  /// Admin: reject game showroom (refund 97.5 ICP, keep 2.5 ICP)
  public shared(msg) func rejectGameShowroom(gameId : Text) : async Result.Result<Text, Text> {
    if (not isAdmin(msg.caller)) return #err("Not authorized");
    hydrateRuntimeStateIfNeeded();
    switch (gameSubmissions.get(gameId)) {
      case null { return #err("Game not found") };
      case (?game) {
        if (game.gameTier != "showroom-pending") return #err("Not pending showroom approval");
        let updated : GameSubmission = {
          id = game.id; name = game.name; developer = game.developer;
          url = game.url; thumbnailUrl = game.thumbnailUrl; description = game.description;
          compatibility = game.compatibility; creator = game.creator;
          gameTier = "backroom"; status = game.status;
          feePaid = game.feePaid; showroomFeePaid = 0;
          txId = game.txId; createdAt = game.createdAt;
        };
        gameSubmissions.put(gameId, updated);
        // Refund 97.5 ICP via the separate refund balance, keep 2.5 ICP.
        let refundAmount = 97_500_000_000; // 97.5 ICP
        creditRefundE8s(game.creator, refundAmount);
        logRevenue("game-showroom", 2_500_000_000, game.creator, 5); // keep 2.5 ICP
        #ok("Game showroom application rejected. 97.5 ICP refund credited.");
      };
    };
  };

  /// Admin: promote game to Jay's Picks
  public shared(msg) func promoteGameToJaysPicks(gameId : Text) : async Result.Result<Text, Text> {
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
        // Refund minus 2.5 ICP, tracked separately from creator earnings.
        let refundAmount = 7_500_000_000; // 7.5 ICP (10 - 2.5)
        creditRefundE8s(game.creator, refundAmount);
        #ok("Game removed. 7.5 ICP refund credited (2.5 ICP removal fee).");
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
        let maxPercent = if (config.highPayoutPercent > config.lowPayoutPercent) {
          config.highPayoutPercent + config.newHighScorePayoutPercent;
        } else {
          config.lowPayoutPercent + config.newHighScorePayoutPercent;
        };
        capTicketJackpotPayout(backedTicketPool * maxPercent / 100, backedTicketPool, DAILY_TICKET_CAP);
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

  /// Get revenue split percentages (Economy v5)
  public query func getRevenueSplits() : async {
    ticketGameCreatorShare : Nat;
    ticketGameDaoShare : Nat;
    ticketGameBurnShare : Nat;
    ticketGamePoolShare : Nat;
    regularGameCreatorShare : Nat;
    regularGameDaoShare : Nat;
    regularGameBurnShare : Nat;
    gameCreatorShare : Nat;
    gameCreatorNonTicketShare : Nat;
    nftCreatorShare : Nat;
  } {
    {
      ticketGameCreatorShare = TICKET_GAME_CREATOR_SHARE;
      ticketGameDaoShare = TICKET_GAME_DAO_SHARE;
      ticketGameBurnShare = TICKET_GAME_BURN_SHARE;
      ticketGamePoolShare = TICKET_GAME_POOL_SHARE;
      regularGameCreatorShare = REGULAR_GAME_CREATOR_SHARE;
      regularGameDaoShare = REGULAR_GAME_DAO_SHARE;
      regularGameBurnShare = REGULAR_GAME_BURN_SHARE;
      gameCreatorShare = TICKET_GAME_CREATOR_SHARE;
      gameCreatorNonTicketShare = REGULAR_GAME_CREATOR_SHARE;
      nftCreatorShare = NFT_CREATOR_SHARE;
    };
  };

  /// Creator/seller claims accumulated ICP-denominated game creator earnings, NFT seller earnings, plus separated ICP refunds.
  /// Funds move from the canister main treasury account into the caller's derived subaccount,
  /// after which the normal withdraw UI can send ICP to any principal or account ID.
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

    let callerSub = principalToSubaccount(caller);
    let selfPrincipal = Principal.fromActor(ArcadeBackend);
    try {
      let result = await ICP_LEDGER.icrc1_transfer({
        to = { owner = selfPrincipal; subaccount = ?callerSub };
        fee = null;
        memo = null;
        from_subaccount = null;
        created_at_time = null;
        amount = balance;
      });
      switch (result) {
        case (#Ok(_blockIndex)) {
          #ok(balance);
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
  // === NFT ESCROW (EXT + ICRC-7) ===
  // ============================================

  /// Confirm that an EXT NFT has been transferred to the arcade canister (escrow)
  /// Verifies on-chain via bearer() that backend now holds the NFT
  public shared(msg) func confirmExtEscrow(listingId : Text, canisterId : Text, extTokenId : Text) : async Result.Result<Text, Text> {
    let caller = msg.caller;
    if (Principal.isAnonymous(caller)) return #err("Must be authenticated");
    hydrateRuntimeStateIfNeeded();
    switch (nftListings.get(listingId)) {
      case null { return #err("Listing not found: " # listingId) };
      case (?listing) {
        if (not Principal.equal(listing.creator, caller) and not isAdmin(caller)) return #err("Not the listing owner");
        if (not Text.equal(listing.sourceCanisterId, canisterId)) return #err("Escrow canister mismatch: expected " # listing.sourceCanisterId # ", got " # canisterId);
        if (not Text.equal(listing.sourceTokenKey, extTokenId)) return #err("Escrow token mismatch: expected " # listing.sourceTokenKey # ", got " # extTokenId);
        switch (escrows.get(listingId)) {
          case (?existing) {
            if (existing.status == "held") {
              // Escrow already confirmed on a previous call — self-heal the listing status if
              // it's still stuck at pending_escrow (this was a real bug: earlier versions of
              // this function never promoted the listing itself), otherwise nothing to do.
              if (listing.status == "pending_escrow") {
                let healedListing : NftListing = { id = listing.id; listingType = listing.listingType; name = listing.name; description = listing.description; rarity = listing.rarity; ticketCost = listing.ticketCost; imageUrl = listing.imageUrl; creator = listing.creator; tier = listing.tier; status = "live"; feePaid = listing.feePaid; showroomFeePaid = listing.showroomFeePaid; txId = listing.txId; createdAt = listing.createdAt; sourceCanisterId = listing.sourceCanisterId; sourceTokenId = listing.sourceTokenId; sourceTokenKey = listing.sourceTokenKey; collectionName = listing.collectionName; };
                nftListings.put(listingId, healedListing);
                return #ok("✅ Listing status repaired — EXT NFT was already escrowed.");
              };
              return #err("NFT already escrowed");
            };
          };
          case null {};
        };
        try {
          let extActor = getExtActor(canisterId);
          let bearerResult = await extActor.bearer(extTokenId);
          switch (bearerResult) {
            case (#ok(accountId)) {
              if (not Text.equal(accountId, arcadeExtAccountId())) return #err(extHoldMismatchMessage(accountId));
              let escrow : EscrowedNft = { listingId; canisterId; tokenId = extTokenId; standard = "ext"; depositor = listing.creator; depositedAt = Time.now(); status = "held"; redeemedBy = null; redeemedAt = null; };
              escrows.put(listingId, escrow);
              let updatedListing : NftListing = { id = listing.id; listingType = listing.listingType; name = listing.name; description = listing.description; rarity = listing.rarity; ticketCost = listing.ticketCost; imageUrl = listing.imageUrl; creator = listing.creator; tier = listing.tier; status = if (listing.status == "pending_escrow") "live" else listing.status; feePaid = listing.feePaid; showroomFeePaid = listing.showroomFeePaid; txId = listing.txId; createdAt = listing.createdAt; sourceCanisterId = listing.sourceCanisterId; sourceTokenId = listing.sourceTokenId; sourceTokenKey = extTokenId; collectionName = listing.collectionName; };
              nftListings.put(listingId, updatedListing);
              #ok("✅ EXT NFT escrowed! " # listing.name # " is now available for purchase.");
            };
            case (#err(e)) { switch (e) { case (#InvalidToken(_)) { #err("Invalid EXT token identifier") }; case (#Other(msg2)) { #err("Bearer check failed: " # msg2) }; }; };
          };
        } catch (e) { #err("EXT verification failed: " # Error.message(e)); };
      };
    };
  };

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
          // Transfer the real ICRC-7 token from the Arcade's own custody to the buyer FIRST;
          // only deduct tickets once that succeeds (fail-safe ordering, matching the escrow path below).
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
            case (#err(errMsg)) { return #err(errMsg) };
            case (#ok(_)) {
              tickets.put(caller, balance - cost);
              let updList : NftListing = { id = listing.id; listingType = listing.listingType; name = listing.name; description = listing.description; rarity = listing.rarity; ticketCost = listing.ticketCost; imageUrl = listing.imageUrl; creator = listing.creator; tier = listing.tier; status = "sold"; feePaid = listing.feePaid; showroomFeePaid = listing.showroomFeePaid; txId = listing.txId; createdAt = listing.createdAt; sourceCanisterId = listing.sourceCanisterId; sourceTokenId = listing.sourceTokenId; sourceTokenKey = listing.sourceTokenKey; collectionName = listing.collectionName; };
              nftListings.put(listingId, updList);
              logRevenue("official-nft-redeem", ticketCostToSellerPayoutE8s(cost), caller, 7);
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

            // Attempt transfer based on standard
            // Transfer NFT based on standard
            let transferOk : Result.Result<Text, Text> = if (escrow.standard == "ext") {
              try {
                let extActor = getExtActor(escrow.canisterId);
                let r = await extActor.transfer({ from = #principal(Principal.fromActor(ArcadeBackend)); to = #principal(caller); token = escrow.tokenId; amount = 1; memo = Blob.fromArray([]); notify = false; subaccount = null; });
                switch (r) { case (#ok(_)) { #ok("ok") }; case (#err(e)) { let m = switch (e) { case (#Unauthorized(_)) { "Unauthorized" }; case (#InsufficientBalance) { "InsufficientBalance" }; case (#Rejected) { "Rejected" }; case (#InvalidToken(_)) { "InvalidToken" }; case (#CannotNotify(_)) { "CannotNotify" }; case (#Other(msg2)) { msg2 }; }; #err("EXT: " # m) }; };
              } catch (e) { #err("EXT call failed: " # Error.message(e)) };
            } else if (escrow.standard == "dip721") {
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
                let sellerPayoutE8s = ticketCostToSellerPayoutE8s(cost);
                // Burn buyer Tickets and credit seller claimable ICP only after NFT transfer success.
                tickets.put(caller, balance - cost);
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
              case (#err(errMsg)) { #err(errMsg) };
            };
          };
        };
      };
    };
  };

  /// Return an escrowed NFT to the original depositor (admin only, for delisting)
  public shared(msg) func returnEscrowNft(listingId : Text) : async Result.Result<Text, Text> {
    if (not isAdmin(msg.caller)) return #err("Not authorized");
    hydrateRuntimeStateIfNeeded();

    switch (escrows.get(listingId)) {
      case null { return #err("No escrow found for listing: " # listingId) };
      case (?escrow) {
        if (escrow.status != "held") return #err("Escrow status is " # escrow.status # " — cannot return");

        let self = Principal.fromActor(ArcadeBackend);
        let returnOk : Result.Result<Text, Text> = if (escrow.standard == "ext") {
          try {
            let extActor = getExtActor(escrow.canisterId);
            let r = await extActor.transfer({ from = #principal(self); to = #principal(escrow.depositor); token = escrow.tokenId; amount = 1; memo = Blob.fromArray([]); notify = false; subaccount = null; });
            switch (r) { case (#ok(_)) { #ok("ok") }; case (#err(_)) { #err("EXT return failed") }; };
          } catch (e) { #err("EXT call: " # Error.message(e)) };
        } else if (escrow.standard == "dip721") {
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
            let updated : EscrowedNft = { listingId = escrow.listingId; canisterId = escrow.canisterId; tokenId = escrow.tokenId; standard = escrow.standard; depositor = escrow.depositor; depositedAt = escrow.depositedAt; status = "returned"; redeemedBy = null; redeemedAt = ?Time.now(); };
            escrows.put(listingId, updated);
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
    let types = ["nft-list", "nft-mint", "nft-showroom", "game-backroom", "game-showroom", "token-purchase", "nft-redeem"];
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
    if (not isAdmin(msg.caller)) return #err("Not authorized");
    hydrateRuntimeStateIfNeeded();
    let current = getTicketBalance(player);
    let newBal = current + amount;
    tickets.put(player, newBal);
    #ok(newBal);
  };

  /// Set tickets to exact amount (admin only) — for resets
  public shared(msg) func adminSetTickets(player : Principal, amount : Nat) : async Result.Result<Nat, Text> {
    if (not isAdmin(msg.caller)) return #err("Not authorized");
    hydrateRuntimeStateIfNeeded();
    tickets.put(player, amount);
    #ok(amount);
  };

  /// Batch credit tickets (admin only)
  public shared(msg) func batchAddTickets(entries : [(Principal, Nat)]) : async Result.Result<Nat, Text> {
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
    if (not isAdmin(msg.caller)) return #err("Not authorized");
    hydrateRuntimeStateIfNeeded();
    costs.put(tokenId, cost);
    #ok();
  };

  /// Batch set NFT costs (admin only)
  public shared(msg) func batchSetNftCosts(entries : [(TokenId, Nat)]) : async Result.Result<(), Text> {
    if (not isAdmin(msg.caller)) return #err("Not authorized");
    hydrateRuntimeStateIfNeeded();
    for ((id, cost) in entries.vals()) {
      costs.put(id, cost);
    };
    #ok();
  };

  /// Set default ticket cost (admin only)
  public shared(msg) func setDefaultCost(cost : Nat) : async Result.Result<(), Text> {
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
    let caller = msg.caller;
    if (Principal.isAnonymous(caller)) return #err("Must be authenticated via Internet Identity");
    hydrateRuntimeStateIfNeeded();

    let balance = getTicketBalance(caller);
    let cost = getCost(tokenId);
    if (balance < cost) {
      return #err("Not enough tickets. Need " # Nat.toText(cost) # " but have " # Nat.toText(balance));
    };

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
          tickets.put(caller, balance - cost);
          let log = Buffer.fromArray<(Principal, TokenId, Int)>(redemptionLog);
          log.add((caller, tokenId, Time.now()));
          redemptionLog := Buffer.toArray(log);
          #ok("NFT #" # Nat.toText(tokenId) # " transferred to your wallet!");
        };
        case (#Err(e)) {
          #err("Transfer failed. The NFT may not be available.");
        };
      };
    } catch (e) {
      #err("Transfer call failed: " # Error.message(e));
    };
  };

  /// Admin transfer NFT from vault to any principal
  public shared(msg) func adminTransfer(tokenId : TokenId, to : Principal) : async Result.Result<Text, Text> {
    if (not isAdmin(msg.caller)) return #err("Not authorized");
    hydrateRuntimeStateIfNeeded();

    try {
      let result = await nftCanister().icrc7_transfer({
        to = { owner = to; subaccount = null };
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
          log.add((to, tokenId, Time.now()));
          redemptionLog := Buffer.toArray(log);
          #ok("NFT #" # Nat.toText(tokenId) # " transferred to " # Principal.toText(to));
        };
        case (#Err(_)) {
          #err("Transfer failed");
        };
      };
    } catch (e) {
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
        created_at_time = null;
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
    if (not isAdmin(msg.caller)) return #err("Admin only");
    await adminWithdrawOperatingTreasuryImpl(destination, amountE8s)
  };

  /// Admin-only withdrawal from the separated Operating Treasury subaccount to a raw ICP ledger account ID.
  /// Amount is the net ICP e8s sent; the operating subaccount must also cover the classic ledger fee.
  public shared(msg) func adminWithdrawOperatingTreasuryToAccountId(toAccountHex : Text, amountE8s : Nat) : async Result.Result<Nat, Text> {
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
        created_at_time = null;
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
        created_at_time = null;
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
        created_at_time = null;
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

  // Debug: return the subaccount hex and check balance via ICRC-1
  func registerHeldExtNftImpl(
    name : Text, description : Text, rarity : Text, ticketCost : Nat,
    imageUrl : Text, canisterId : Text, extTokenId : Text,
    collectionName : Text, creatorPrincipal : Principal
  ) : async Result.Result<Text, Text> {
    hydrateRuntimeStateIfNeeded();
    if (Text.size(name) == 0) return #err("Name required");
    if (Text.size(canisterId) == 0) return #err("EXT canister ID required");
    if (Text.size(extTokenId) == 0) return #err("EXT token identifier required");
    if (ticketCost < 25) return #err("Minimum ticket cost is 25");

    try {
      let extActor = getExtActor(canisterId);
      let bearerResult = await extActor.bearer(extTokenId);
      switch (bearerResult) {
        case (#ok(accountId)) {
          if (not Text.equal(accountId, arcadeExtAccountId())) return #err(extHoldMismatchMessage(accountId));
        };
        case (#err(e)) {
          let msg = switch (e) { case (#InvalidToken(_)) { "Invalid EXT token identifier" }; case (#Other(msg2)) { msg2 } };
          return #err("Bearer check failed: " # msg # ". Expected/current arcade account: " # arcadeExtAccountId());
        };
      };
    } catch (e) { return #err("EXT bearer check failed: " # Error.message(e)) };

    let id = genListingId("nft-ex");
    let listing : NftListing = {
      id = id; listingType = "existing"; name = name; description = description;
      rarity = rarity; ticketCost = ticketCost; imageUrl = imageUrl;
      creator = creatorPrincipal; tier = "open"; status = "live";
      feePaid = 0; showroomFeePaid = 0; txId = 0;
      createdAt = Time.now(); sourceCanisterId = canisterId;
      sourceTokenId = 0; sourceTokenKey = extTokenId; collectionName = collectionName;
    };
    nftListings.put(id, listing);
    let escrow : EscrowedNft = {
      listingId = id; canisterId = canisterId; tokenId = extTokenId;
      standard = "ext"; depositor = creatorPrincipal; depositedAt = Time.now();
      status = "held"; redeemedBy = null; redeemedAt = null;
    };
    escrows.put(id, escrow);
    #ok(id)
  };

  // Admin: register an already-held EXT NFT (creates listing + escrow in one call)
  public shared(msg) func adminRegisterHeldExtNft(
    name : Text, description : Text, rarity : Text, ticketCost : Nat,
    imageUrl : Text, canisterId : Text, extTokenId : Text,
    collectionName : Text, creatorPrincipal : Principal
  ) : async Result.Result<Text, Text> {
    if (not isAdmin(msg.caller)) return #err("Admin only");
    await registerHeldExtNftImpl(name, description, rarity, ticketCost, imageUrl, canisterId, extTokenId, collectionName, creatorPrincipal)
  };

  // Legacy-compatible wrapper retained for existing admin tooling.
  public shared(msg) func adminRegisterHeldNft(
    name : Text, description : Text, rarity : Text, ticketCost : Nat,
    imageUrl : Text, canisterId : Text, extTokenId : Text,
    collectionName : Text, creatorPrincipal : Principal
  ) : async Result.Result<Text, Text> {
    if (not isAdmin(msg.caller)) return #err("Admin only");
    await registerHeldExtNftImpl(name, description, rarity, ticketCost, imageUrl, canisterId, extTokenId, collectionName, creatorPrincipal)
  };

  // Admin: return an orphaned held EXT NFT by account id even when no escrow/listing exists.
  public shared(msg) func adminReturnHeldExtNft(canisterId : Text, extTokenId : Text, toAccountId : Text) : async Result.Result<Text, Text> {
    if (not isAdmin(msg.caller)) return #err("Admin only");
    hydrateRuntimeStateIfNeeded();
    if (Text.size(canisterId) == 0) return #err("EXT canister ID required");
    if (Text.size(extTokenId) == 0) return #err("EXT token identifier required");
    if (Text.size(Text.trim(toAccountId, #char ' ')) == 0) return #err("Recipient EXT account id required");

    try {
      let extActor = getExtActor(canisterId);
      let bearerResult = await extActor.bearer(extTokenId);
      switch (bearerResult) {
        case (#ok(accountId)) {
          if (not Text.equal(accountId, arcadeExtAccountId())) return #err(extHoldMismatchMessage(accountId));
        };
        case (#err(e)) {
          let msg = switch (e) { case (#InvalidToken(_)) { "Invalid EXT token identifier" }; case (#Other(msg2)) { msg2 } };
          return #err("Bearer check failed: " # msg # ". Expected/current arcade account: " # arcadeExtAccountId());
        };
      };

      let r = await extActor.transfer({ from = #principal(Principal.fromActor(ArcadeBackend)); to = #address(toAccountId); token = extTokenId; amount = 1; memo = Blob.fromArray([]); notify = false; subaccount = null; });
      switch (r) {
        case (#ok(_)) { #ok("EXT NFT returned to account " # toAccountId) };
        case (#err(e)) {
          let m = switch (e) { case (#Unauthorized(msg2)) { "Unauthorized: " # msg2 }; case (#InsufficientBalance) { "InsufficientBalance" }; case (#Rejected) { "Rejected" }; case (#InvalidToken(msg2)) { "InvalidToken: " # msg2 }; case (#CannotNotify(msg2)) { "CannotNotify: " # msg2 }; case (#Other(msg2)) { msg2 }; };
          #err("EXT return failed: " # m)
        };
      }
    } catch (e) { #err("EXT return call failed: " # Error.message(e)) }
  };

  // Check who holds an EXT NFT
  public func checkExtBearer(canisterId : Text, tokenId : Text) : async Result.Result<Text, Text> {
    try {
      let extActor = getExtActor(canisterId);
      let resp = await extActor.bearer(tokenId);
      switch (resp) {
        case (#ok(accountId)) { #ok(accountId) };
        case (#err(_)) { #err("Token not found or error") };
      }
    } catch (e) {
      #err("Call failed: " # Error.message(e))
    }
  };

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
    var total : Nat = 0;
    for (badge in getBadgesForOwner(owner).vals()) { total += badge.votingPower };
    total;
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
    if (isDaoSection(section) and not hasDaoAccess(msg.caller)) return [];
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
    if (isAnonymousPrincipal(msg.caller)) return #err("Connect wallet to post");
    switch (validateForumText(section, "Section", FORUM_SECTION_MAX_CHARS, true)) { case (#err(e)) return #err(e); case (#ok(())) {} };
    switch (validateForumText(title, "Title", FORUM_TITLE_MAX_CHARS, true)) { case (#err(e)) return #err(e); case (#ok(())) {} };
    switch (validateForumText(body, "Body", FORUM_BODY_MAX_CHARS, false)) { case (#err(e)) return #err(e); case (#ok(())) {} };
    switch (validateForumText(authorName, "Author", FORUM_AUTHOR_MAX_CHARS, false)) { case (#err(e)) return #err(e); case (#ok(())) {} };
    let normalizedImage = switch (validateForumImage(msg.caller, image)) { case (#ok(v)) v; case (#err(e)) return #err(e) };
    if (Text.size(Text.trim(body, #char ' ')) == 0 and Option.isNull(normalizedImage)) return #err("Body required for text-first forum posting");
    if (isDaoSection(section) and not hasDaoAccess(msg.caller)) return #err("Voting Power Badge required for DAO forum posting");
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
    forumThreadEntries := Array.append<ForumThread>([thread], forumThreadEntries);
    ensureForumIndexBuilt();
    addThreadToIndex(thread);
    #ok(id)
  };

  public shared(msg) func addForumReply(threadId : Text, body : Text, image : ?Text, authorName : Text, parentReplyId : ?Text) : async Result.Result<Text, Text> {
    if (isAnonymousPrincipal(msg.caller)) return #err("Connect wallet to reply");
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
      if (isDaoSection(thread.section) and not hasDaoAccess(msg.caller)) {
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

  public query func getGamerBadges(owner : Principal) : async [GamerBadge] {
    getBadgesForOwner(owner);
  };

  public query func getVotingPower(owner : Principal) : async Nat { votingPowerOf(owner) };

  public shared(msg) func awardDevContributorBadge(owner : Principal, gameId : Text) : async Result.Result<Text, Text> {
    if (not isAdmin(msg.caller)) return #err("Admin only");
    gamerBadgeCounter += 1;
    let badge : GamerBadge = { id = "badge-" # Nat.toText(gamerBadgeCounter); badgeType = "dev-contributor"; owner = owner; gameId = ?gameId; votingPower = 5; soulbound = true; createdAt = Time.now() };
    gamerBadgeEntries := Array.append<GamerBadge>(gamerBadgeEntries, [badge]);
    ensureBadgeIndexBuilt();
    addBadgeToIndex(badge);
    #ok(badge.id)
  };

  public shared(msg) func awardArtistContributorBadge(owner : Principal) : async Result.Result<Text, Text> {
    if (not isAdmin(msg.caller)) return #err("Admin only");
    gamerBadgeCounter += 1;
    let badge : GamerBadge = { id = "badge-" # Nat.toText(gamerBadgeCounter); badgeType = "artist-contributor"; owner = owner; gameId = null; votingPower = 5; soulbound = true; createdAt = Time.now() };
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
    if (isAnonymousPrincipal(msg.caller)) return #err("Connect wallet to buy a badge");
    let owned = vpBadgeCountOf(msg.caller);
    if (owned >= 10) return #err("All 10 Voting Power Badges already owned");
    let cost = VP_BADGE_COSTS[owned];
    let balance = getTicketBalance(msg.caller);
    if (balance < cost) return #err("Not enough tickets. This badge costs " # Nat.toText(cost) # " Tickets. Have " # Nat.toText(balance));
    tickets.put(msg.caller, balance - cost);
    gamerBadgeCounter += 1;
    let badge : GamerBadge = { id = "badge-" # Nat.toText(gamerBadgeCounter); badgeType = "vp-badge-" # Nat.toText(owned + 1); owner = msg.caller; gameId = null; votingPower = 1; soulbound = true; createdAt = Time.now() };
    gamerBadgeEntries := Array.append<GamerBadge>(gamerBadgeEntries, [badge]);
    ensureBadgeIndexBuilt();
    addBadgeToIndex(badge);
    #ok(badge.id)
  };

  public shared(msg) func adminGrantAllVpBadges() : async Result.Result<Text, Text> {
    if (not isAdmin(msg.caller)) return #err("Not authorized");
    var i = vpBadgeCountOf(msg.caller);
    while (i < 10) {
      gamerBadgeCounter += 1;
      let badge : GamerBadge = { id = "badge-" # Nat.toText(gamerBadgeCounter); badgeType = "vp-badge-" # Nat.toText(i + 1); owner = msg.caller; gameId = null; votingPower = 1; soulbound = true; createdAt = Time.now() };
      gamerBadgeEntries := Array.append<GamerBadge>(gamerBadgeEntries, [badge]);
      ensureBadgeIndexBuilt();
      addBadgeToIndex(badge);
      i += 1;
    };
    #ok("All 10 Voting Power Badges granted")
  };

  public shared(msg) func adminResetVpBadges() : async Result.Result<Text, Text> {
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
    if (not isAdmin(msg.caller)) return #err("Not authorized");
    hydrateRuntimeStateIfNeeded();
    if (Text.size(Text.trim(canisterId, #char ' ')) == 0) return #err("Canister ID required");
    if (Text.size(Text.trim(name, #char ' ')) == 0) return #err("Collection name required");
    externalCollections.put(canisterId, name);
    #ok("External collection registered")
  };

  public shared(msg) func adminRemoveExternalCollection(canisterId : Text) : async Result.Result<Text, Text> {
    if (not isAdmin(msg.caller)) return #err("Not authorized");
    hydrateRuntimeStateIfNeeded();
    externalCollections.delete(canisterId);
    #ok("External collection removed")
  };

  public query func getExternalCollections() : async [(Text, Text)] {
    Iter.toArray(externalCollections.entries())
  };

  public shared(msg) func adminAddModerator(principal : Principal) : async Result.Result<Text, Text> {
    if (not isAdmin(msg.caller)) return #err("Not authorized");
    hydrateRuntimeStateIfNeeded();
    switch (moderators.get(principal)) {
      case (?_) { #err("Already a moderator") };
      case null { moderators.put(principal, []); #ok("Moderator added") };
    }
  };

  public shared(msg) func adminRemoveModerator(principal : Principal) : async Result.Result<Text, Text> {
    if (not isAdmin(msg.caller)) return #err("Not authorized");
    hydrateRuntimeStateIfNeeded();
    moderators.delete(principal);
    #ok("Moderator removed")
  };

  public query func getModerators() : async [Principal] {
    Iter.toArray(moderators.keys())
  };

  public shared(msg) func createProposal(title : Text, body : Text, category : Text, duration : Text, images : [Text], paymentLane : Text) : async Result.Result<Text, Text> {
    if (isAnonymousPrincipal(msg.caller)) return #err("Connect wallet to create a proposal");
    let vp = votingPowerOf(msg.caller);
    if (vp < 3 and not isAdmin(msg.caller)) return #err("3 Voting Power required to create proposals");
    if (Text.size(Text.trim(title, #char ' ')) == 0) return #err("Title required");
    if (Text.size(Text.trim(body, #char ' ')) == 0) return #err("Description required");
    if (not isAdmin(msg.caller)) {
      if (paymentLane == "tickets") {
        let ticketBal = getTicketBalance(msg.caller);
        if (ticketBal < 10) return #err("Not enough tickets. Creating a proposal costs 10 Tickets. Have " # Nat.toText(ticketBal));
        tickets.put(msg.caller, ticketBal - 10);
      } else {
        let tokenBal = getTokenBalance(msg.caller);
        if (tokenBal < 5) return #err("Not enough tokens. Creating a proposal costs 5 Tokens. Have " # Nat.toText(tokenBal));
        tokens.put(msg.caller, tokenBal - 5);
      };
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

  public shared(msg) func castVote(proposalId : Text, vote : Text) : async Result.Result<Text, Text> {
    if (isAnonymousPrincipal(msg.caller)) return #err("Connect wallet to vote");
    if (vote != "for" and vote != "against") return #err("Vote must be for or against");
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
      let effectiveWeight = if (isAdmin(msg.caller) and weight == 0) 1 else weight;
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
    addDxp(msg.caller, badgeCountOf(msg.caller));
    #ok("Vote recorded")
  };

  public shared(msg) func addProposalReply(proposalId : Text, body : Text) : async Result.Result<Text, Text> {
    if (isAnonymousPrincipal(msg.caller)) return #err("Connect wallet to reply");
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
};
