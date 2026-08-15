import fs from 'node:fs';
import assert from 'node:assert/strict';

const source = fs.readFileSync('backend/main.mo', 'utf8');

const requiredFragments = [
  'type OfficialCollection = {',
  'stable var officialCollectionEntries',
  'stable var officialCollectionAbilityEntries',
  'transient var officialCollections = HashMap.HashMap<Text, OfficialCollection>',
  'public query func getOfficialCollections() : async [OfficialCollection]',
  'public query func getOfficialCollection(collectionId : Text) : async ?OfficialCollection',
  'public shared(msg) func adminCreateCollection(name : Text, description : Text, ticketCost : Nat, imageUrls : [Text]) : async Result.Result<Text, Text>',
  'public shared(msg) func adminMintCollection(collectionId : Text) : async Result.Result<Text, Text>',
  'public shared(msg) func adminDeleteCollection(collectionId : Text) : async Result.Result<Bool, Text>',
  'public shared(msg) func adminDeleteCol(collectionId : Text) : async Result.Result<Bool, Text>',
  'public query func adminGetCollectionTokenAbilities(collectionId : Text) : async [(Nat, Text)]',
  'public shared(msg) func adminAssignAbility(tokenId : Nat, ability : Text) : async Result.Result<Text, Text>',
  'public shared(msg) func adminSetCollectionTokenAbility(collectionId : Text, tokenId : Nat, ability : Text) : async Result.Result<Text, Text>',
  'public shared(msg) func adminRemoveAbility(tokenId : Nat) : async Result.Result<Text, Text>',
  'public shared(msg) func adminClearCollectionTokenAbility(collectionId : Text, tokenId : Nat) : async Result.Result<Text, Text>',
  'collectionName = collection.name',
  'listingType = "mint"',
  'status = "live"',
  'tier = "open"',
  'sourceTokenKey = "official:" # collection.id # ":" # Nat.toText(tokenId)',
];

for (const fragment of requiredFragments) {
  assert.ok(source.includes(fragment), `backend/main.mo missing official collection fragment: ${fragment}`);
}

const collectionTypeBlock = source.match(/type OfficialCollection = \{[\s\S]*?\n  \};/);
assert.ok(collectionTypeBlock, 'OfficialCollection type block should exist');
for (const field of ['id : Text', 'name : Text', 'description : Text', 'creator : Principal', 'imageUrls : [Text]', 'nftIds : [Nat]', 'ticketCost : Nat', 'totalSupply : Nat', 'abilities : [(Text, Text)]', 'createdAt : Int']) {
  assert.ok(collectionTypeBlock[0].includes(field), `OfficialCollection missing field ${field}`);
}

const createIndex = source.indexOf('public shared(msg) func adminCreateCollection');
const mintIndex = source.indexOf('public shared(msg) func adminMintCollection');
assert.ok(createIndex > -1 && mintIndex > createIndex, 'mint method should follow create method');

console.log('official collections backend static contract ok');
