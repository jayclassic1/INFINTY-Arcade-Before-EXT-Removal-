import Array "mo:base/Array";
import Buffer "mo:base/Buffer";
import Hash "mo:base/Hash";
import HashMap "mo:base/HashMap";
import Iter "mo:base/Iter";
import Nat "mo:base/Nat";
import Nat32 "mo:base/Nat32";
import Option "mo:base/Option";
import Principal "mo:base/Principal";
import Text "mo:base/Text";
import Time "mo:base/Time";

persistent actor NftCanister {

  // Types
  public type Account = {
    owner : Principal;
    subaccount : ?Blob;
  };

  public type TransferArg = {
    from : ?Account;
    to : Account;
    token_ids : [Nat];
    memo : ?Blob;
    created_at_time : ?Nat64;
    is_atomic : ?Bool;
    spender_subaccount : ?Blob;
  };

  public type TransferError = {
    #Unauthorized;
    #TooOld;
    #CreatedInFuture : { ledger_time : Nat64 };
    #Duplicate : { duplicate_of : Nat };
    #GenericError : { error_code : Nat; message : Text };
    #GenericBatchError : { error_code : Nat; message : Text };
  };

  public type TransferResult = {
    #Ok : [Nat];
    #Err : TransferError;
  };

  public type Metadata = [(Text, MetadataValue)];

  public type MetadataValue = {
    #Nat : Nat;
    #Int : Int;
    #Text : Text;
    #Blob : Blob;
    #Map : [(Text, MetadataValue)];
    #Array : [MetadataValue];
  };

  // State
  stable var nextTokenId : Nat = 0;
  stable var tokenOwners : [(Nat, Account)] = [];
  stable var tokenMetadata : [(Nat, Metadata)] = [];
  stable var collectionName : Text = "Infinity Arcade NFTs";
  stable var collectionSymbol : Text = "IANFT";
  stable var collectionDescription : Text = "NFTs for the Infinity Arcade on-chain gaming platform";
  stable var collectionLogo : Text = ""; // URL to collection logo image

  // Admin
  stable var admins : [Principal] = [
    Principal.fromText("6fuxu-dcmul-k6b5r-gdbkr-4fiqy-dgdjx-efdj3-hvqsx-3pfiu-bnc7x-qae"),
    Principal.fromText("fvuhj-qdha4-tu5gc-4hvim-yaxae-g5grp-xjiz3-u5rpo-5cniw-gpolf-eqe")
  ];

  // Approved operators (for arcade backend canister to transfer)
  stable var approvedOperators : [Principal] = [];

  // In-memory maps
  transient var ownerMap = HashMap.HashMap<Nat, Account>(64, Nat.equal, func(n : Nat) : Hash.Hash { Nat32.fromNat(n % 2147483647) });
  transient var metaMap = HashMap.HashMap<Nat, Metadata>(64, Nat.equal, func(n : Nat) : Hash.Hash { Nat32.fromNat(n % 2147483647) });

  // Rebuild maps from stable storage
  transient let _ : () = do {
    for ((id, acct) in tokenOwners.vals()) { ownerMap.put(id, acct) };
    for ((id, meta) in tokenMetadata.vals()) { metaMap.put(id, meta) };
  };

  func isAdmin(p : Principal) : Bool {
    for (a in admins.vals()) { if (Principal.equal(a, p)) return true };
    false
  };

  func isOperator(p : Principal) : Bool {
    for (o in approvedOperators.vals()) { if (Principal.equal(o, p)) return true };
    false
  };

  func accountsEqual(a : Account, b : Account) : Bool {
    Principal.equal(a.owner, b.owner) and a.subaccount == b.subaccount
  };

  // Pre-upgrade: save maps to stable
  system func preupgrade() {
    let ownerBuf = Buffer.Buffer<(Nat, Account)>(ownerMap.size());
    for (entry in ownerMap.entries()) { ownerBuf.add(entry) };
    tokenOwners := Buffer.toArray(ownerBuf);

    let metaBuf = Buffer.Buffer<(Nat, Metadata)>(metaMap.size());
    for (entry in metaMap.entries()) { metaBuf.add(entry) };
    tokenMetadata := Buffer.toArray(metaBuf);
  };

  // ============ ICRC-7 Standard Queries ============

  public shared query func icrc7_collection_metadata() : async Metadata {
    [
      ("icrc7:name", #Text(collectionName)),
      ("icrc7:symbol", #Text(collectionSymbol)),
      ("icrc7:description", #Text(collectionDescription)),
      ("icrc7:total_supply", #Nat(ownerMap.size())),
    ]
  };

  public shared query func icrc7_name() : async Text { collectionName };
  public shared query func icrc7_symbol() : async Text { collectionSymbol };
  public shared query func icrc7_description() : async Text { collectionDescription };
  public shared query func icrc7_total_supply() : async Nat { ownerMap.size() };

  // Logo for marketplace display
  public shared query func icrc7_logo() : async ?Text { ?collectionLogo };

  // Paginated token listing — marketplaces use this to enumerate all tokens
  public shared query func icrc7_tokens(prev : ?Nat, take : ?Nat) : async [Nat] {
    let limit = switch (take) { case (?t) { if (t > 500) 500 else t }; case null { 100 } };
    let start = switch (prev) { case (?p) { p + 1 }; case null { 0 } };
    let buf = Buffer.Buffer<Nat>(limit);
    var id = start;
    while (id < nextTokenId and buf.size() < limit) {
      switch (ownerMap.get(id)) {
        case (?_) { buf.add(id) };
        case null {}; // deleted/burned token, skip
      };
      id += 1;
    };
    Buffer.toArray(buf)
  };

  // Standard declaration — tells marketplaces what we support
  public shared query func icrc7_supported_standards() : async [{name : Text; url : Text}] {
    [{name = "ICRC-7"; url = "https://github.com/dfinity/ICRC/blob/main/ICRCs/ICRC-7/ICRC-7.md"}]
  };

  // Max memo size for transfers
  public shared query func icrc7_max_memo_size() : async ?Nat { ?256 };

  // Max update batch size
  public shared query func icrc7_max_update_batch_size() : async ?Nat { ?100 };

  // Max query batch size
  public shared query func icrc7_max_query_batch_size() : async ?Nat { ?500 };

  // Default take value for paginated queries
  public shared query func icrc7_max_take_value() : async ?Nat { ?500 };

  // Atomic batch transfers supported
  public shared query func icrc7_atomic_batch_transfers() : async ?Bool { ?true };

  public shared query func icrc7_owner_of(tokenId : Nat) : async {
    #Ok : Account;
    #Err : { #InvalidTokenId };
  } {
    switch (ownerMap.get(tokenId)) {
      case (?acct) { #Ok(acct) };
      case null { #Err(#InvalidTokenId) };
    }
  };

  public shared query func icrc7_token_metadata(tokenId : Nat) : async ?Metadata {
    metaMap.get(tokenId)
  };

  public shared query func icrc7_tokens_of(account : Account) : async [Nat] {
    let buf = Buffer.Buffer<Nat>(16);
    for ((id, acct) in ownerMap.entries()) {
      if (accountsEqual(acct, account)) { buf.add(id) };
    };
    Buffer.toArray(buf)
  };

  public shared query func icrc7_balance_of(account : Account) : async Nat {
    var count : Nat = 0;
    for ((_, acct) in ownerMap.entries()) {
      if (accountsEqual(acct, account)) { count += 1 };
    };
    count
  };

  // ============ ICRC-7 Transfer ============

  public shared(msg) func icrc7_transfer(args : TransferArg) : async TransferResult {
    let caller = msg.caller;

    // Check each token
    let successIds = Buffer.Buffer<Nat>(args.token_ids.size());

    for (tokenId in args.token_ids.vals()) {
      switch (ownerMap.get(tokenId)) {
        case null {
          return #Err(#GenericError({ error_code = 1; message = "Token " # Nat.toText(tokenId) # " does not exist" }));
        };
        case (?currentOwner) {
          // Caller must be the token's owner or an approved operator (the arcade_backend
          // canister itself, acting as the system). Being a human admin grants NO special
          // transfer bypass here — not even Jay's own admin account can freely move an
          // Official NFT. This is intentional: "not even admin" is the whole point of the
          // closed-loop policy, so admin is bound by the exact same rules as any other owner.
          let isOwner = Principal.equal(caller, currentOwner.owner);
          let isOperatorCaller = isOperator(caller);
          if (not isOwner and not isOperatorCaller) {
            return #Err(#Unauthorized);
          };
          // Closed-loop rule: a plain token owner (including an admin who happens to own a
          // token personally) may only ever send it INTO arcade custody (i.e. to an approved
          // operator) — never to any other wallet or outside marketplace. Operator-initiated
          // transfers (the arcade_backend canister itself moving a token from its own custody
          // to a redeeming buyer) are the one exception, since that's the system fulfilling a
          // real purchase, not a person sending an NFT.
          if (isOwner and not isOperatorCaller and not isOperator(args.to.owner)) {
            return #Err(#Unauthorized);
          };
          ownerMap.put(tokenId, args.to);
          successIds.add(tokenId);
        };
      };
    };

    #Ok(Buffer.toArray(successIds))
  };

  // ============ Minting (Admin only) ============

  public shared(msg) func mint(to : Account, metadata : Metadata) : async Nat {
    assert(isAdmin(msg.caller) or isOperator(msg.caller));
    let tokenId = nextTokenId;
    nextTokenId += 1;
    ownerMap.put(tokenId, to);
    metaMap.put(tokenId, metadata);
    tokenId
  };

  public shared(msg) func mintBatch(to : Account, metadataList : [Metadata]) : async [Nat] {
    assert(isAdmin(msg.caller) or isOperator(msg.caller));
    let ids = Buffer.Buffer<Nat>(metadataList.size());
    for (meta in metadataList.vals()) {
      let tokenId = nextTokenId;
      nextTokenId += 1;
      ownerMap.put(tokenId, to);
      metaMap.put(tokenId, meta);
      ids.add(tokenId);
    };
    Buffer.toArray(ids)
  };

  // ============ Admin Functions ============

  public shared(msg) func addOperator(operator : Principal) : async () {
    assert(isAdmin(msg.caller));
    let buf = Buffer.Buffer<Principal>(approvedOperators.size() + 1);
    for (o in approvedOperators.vals()) { buf.add(o) };
    buf.add(operator);
    approvedOperators := Buffer.toArray(buf);
  };

  public shared(msg) func removeOperator(operator : Principal) : async () {
    assert(isAdmin(msg.caller));
    approvedOperators := Array.filter<Principal>(approvedOperators, func(o) { not Principal.equal(o, operator) });
  };

  // Admin: set collection logo URL
  public shared(msg) func setCollectionLogo(logo : Text) : async () {
    assert(isAdmin(msg.caller));
    collectionLogo := logo;
  };

  public shared(msg) func addAdmin(admin : Principal) : async () {
    assert(isAdmin(msg.caller));
    let buf = Buffer.Buffer<Principal>(admins.size() + 1);
    for (a in admins.vals()) { buf.add(a) };
    buf.add(admin);
    admins := Buffer.toArray(buf);
  };

  public shared(msg) func setCollectionMetadata(name : Text, symbol : Text, description : Text) : async () {
    assert(isAdmin(msg.caller));
    collectionName := name;
    collectionSymbol := symbol;
    collectionDescription := description;
  };

  // ============ Utility ============

  public shared query func getOperators() : async [Principal] { approvedOperators };
  public shared query func getAdmins() : async [Principal] { admins };
}
